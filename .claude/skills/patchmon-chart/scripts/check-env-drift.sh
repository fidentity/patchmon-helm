#!/bin/sh
# Compares the environment variables this chart sets against the ones the
# PatchMon server actually reads, in both directions.
#
# The application's config loader is the authority, not its documentation: the
# archived chart shipped AUTO_CREATE_ROLE_PERMISSIONS and PM_LOG_TO_CONSOLE
# long after 2.x stopped reading either.
#
# Usage:
#   check-env-drift.sh                  clones PatchMon into a temp dir
#   check-env-drift.sh /path/to/PatchMon  reuses an existing checkout
#
# Needs: helm, python3 + PyYAML, and git when no checkout is given.
set -eu

CHART=$(cd "$(dirname "$0")/../../../.." && pwd)
APP=${1:-}
CLEANUP=""

if [ -z "$APP" ]; then
  APP=$(mktemp -d)
  CLEANUP=$APP
  echo "--> cloning PatchMon into $APP"
  git clone --quiet --depth 1 https://github.com/PatchMon/PatchMon.git "$APP"
fi
RENDER=""
trap 'rm -f "$RENDER"; test -n "$CLEANUP" && rm -rf "$CLEANUP"' EXIT

SRC="$APP/server-source-code"
test -d "$SRC" || { echo "no server-source-code in $APP" >&2; exit 1; }

echo "--> rendering the chart with everything switched on"
RENDER=$(mktemp)
helm template patchmon "$CHART" \
  --set server.jwtSecret=x --set server.aiEncryptionKey=x \
  --set database.auth.password=x --set redis.auth.password=x \
  --set server.oidc.enabled=true \
  --set server.oidc.issuerUrl=https://issuer.example.com \
  --set server.oidc.clientId=id --set server.oidc.clientSecret=secret \
  --set 'server.oidc.groups.admin=admins' \
  --set 'server.oidc.groups.superadmin=supers' \
  --set 'server.oidc.groups.hostManager=hosts' \
  --set 'server.oidc.groups.user=users' \
  --set 'server.oidc.groups.readonly=readers' \
  > "$RENDER"

CHART_DIR=$CHART APP_SRC=$SRC RENDER_FILE=$RENDER python3 - <<'PY'
import os, re, sys, glob, yaml

render = os.environ["RENDER_FILE"]
src = os.environ["APP_SRC"]
chart = os.environ["CHART_DIR"]

# What the chart puts into the server container.
emitted = set()
for doc in yaml.safe_load_all(open(render)):
    if not doc or doc.get("kind") not in ("StatefulSet", "Deployment"):
        continue
    labels = doc["spec"]["template"]["metadata"].get("labels", {})
    if labels.get("app.kubernetes.io/component") != "server":
        continue
    for c in doc["spec"]["template"]["spec"]["containers"]:
        for e in c.get("env", []):
            emitted.add(e["name"])

# Tier 1: read through a known environment accessor. This is the authority.
read = set()
ACCESSOR = r'(?:os\.Getenv|os\.LookupEnv|getEnv|getEnvInt|getEnvBytes|getEnvBytesKBDefault)\w*\(\s*"([A-Z][A-Z0-9_]*)"'
for path in glob.glob(f"{src}/**/*.go", recursive=True):
    body = open(path, errors="replace").read()
    read |= set(re.findall(ACCESSOR, body))

# Tier 2: appears anywhere in the Go source as an upper-case string literal.
# Deliberately loose. Variables reached through a local wrapper rather than a
# recognised accessor land here — SERVER_PROTOCOL, SERVER_HOST and SERVER_PORT
# are read by an `env(...)` helper in internal/handler/settings.go for the
# diagnostics page, and reporting those as dead would get working config
# deleted. So tier 2 downgrades a finding to REVIEW instead of failing.
mentioned = set()
for path in glob.glob(f"{src}/**/*.go", recursive=True):
    body = open(path, errors="replace").read()
    mentioned |= set(re.findall(r'"([A-Z][A-Z0-9_]{2,})"', body))

# Set by the chart for its own use, not read by the server: DATABASE_URL
# interpolates it as $(POSTGRES_PASSWORD) via kubelet.
CHART_INTERNAL = {"POSTGRES_PASSWORD"}

dead = sorted(e for e in emitted if e not in read and e not in mentioned and e not in CHART_INTERNAL)
review = sorted(e for e in emitted if e not in read and e in mentioned and e not in CHART_INTERNAL)
# Informational only: most variables are optional by design, because PatchMon
# resolves settings as environment > database > default and the chart
# deliberately leaves the optional ones unset so the Settings UI owns them.
unmodelled = sorted(r for r in read if r not in emitted)

status = 0
print(f"\nchart sets {len(emitted)} variables; server reads {len(read)}\n")

if dead:
    status = 1
    print("DEAD - the chart sets these and they appear nowhere in the server source:")
    for name in dead:
        print(f"  {name}")
    print("  -> remove from templates/_helpers.tpl (envMap) and values.yaml\n")
else:
    print("DEAD: none\n")

if review:
    print("REVIEW - set by the chart, not read through a known accessor, but")
    print("present in the source. Usually reached via a local wrapper. Confirm")
    print("by hand before removing anything:")
    for name in review:
        print(f"  {name}    grep -rn '\"{name}\"' server-source-code/")
    print()

# Cross-check the envMap against values.yaml while we are here.
tpl = open(f"{chart}/templates/_helpers.tpl").read()
block = re.search(r'define "patchmon\.server\.envMap".*?\n(.*?)\{\{- end -\}\}', tpl, re.S)
if block:
    mapping = yaml.safe_load(block.group(1))
    env_values = yaml.safe_load(open(f"{chart}/values.yaml"))["server"]["env"]
    orphan_keys = [k for k in mapping.values() if k not in env_values]
    if orphan_keys:
        status = 1
        print("envMap points at server.env keys that do not exist:")
        for k in orphan_keys:
            print(f"  {k}")
        print()
    stale = sorted(name for name in mapping if name not in read and name not in mentioned)
    if stale:
        status = 1
        print("envMap names variables absent from the server source entirely:")
        for name in stale:
            print(f"  {name}")
        print()

print(f"NOT MODELLED ({len(unmodelled)}) - the server reads these, the chart does not set them.")
print("Expected for anything optional: leaving it unset is what keeps the")
print("setting editable in the Settings UI. Review only for new required ones.")
for name in unmodelled:
    print(f"  {name}")

sys.exit(status)
PY
