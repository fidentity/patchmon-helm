#!/bin/sh
# Lints the chart and renders every example, before it is packaged.
#
# Wired to package.json's prebuild:helm, so a chart that does not render never
# reaches the registry. Run from ./deployment; the chart is the parent.
set -eu

cd "$(dirname "$0")/.."

# The chart refuses to render without these, by design: it generates no
# secrets, because a value that changed on every upgrade would invalidate every
# session and make every encrypted column unreadable. Placeholders are enough
# to render.
LINT_SECRETS="--set server.jwtSecret=lint \
  --set server.aiEncryptionKey=lint \
  --set database.auth.password=lint \
  --set redis.auth.password=lint"

echo "--> helm lint"
# shellcheck disable=SC2086
helm lint . $LINT_SECRETS

echo "--> helm template (default values)"
# shellcheck disable=SC2086
helm template patchmon . $LINT_SECRETS >/dev/null

echo "--> helm template (examples)"
for f in examples/*.yaml; do
  printf '    %s\n' "$f"
  helm template patchmon . -f "$f" >/dev/null
done

echo "--> ok"
