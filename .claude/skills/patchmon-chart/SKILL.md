---
name: patchmon-chart
description: Maintain, verify or release the PatchMon Helm chart in this repository — tracking a new upstream PatchMon version, adding or changing values, debugging what the chart renders, or publishing it. Use whenever work touches Chart.yaml, values.yaml, templates/, deployment/ or the CI that publishes the chart.
---

# Maintaining the PatchMon Helm chart

This repository is a **chart only**. The images it deploys are upstream's
(`ghcr.io/patchmon/patchmon-server`) plus third-party postgres, redis and
guacd. Nothing here builds a container.

`values.yaml` is the product. It is the interface operators configure the
release through, and it is commented as documentation — treat a change to it as
a change to a public API, not an internal detail.

## Read these first

| File | Why |
|---|---|
| `values.yaml` | the complete reference; every option is commented with its reasoning |
| `UPDATE.md` | the release procedure, version scheme and publishing matrix |
| `docs/upgrading-1x-to-2x.md` | what changed from the 1.4.x chart, and the migration traps |
| `NOTICE` | provenance — this is a GPL-3.0 derivative of an archived community chart |

## Repository shape

```
Chart.yaml  values.yaml  templates/     the chart, plain Helm
deployment/                             npm build wrapper — NOT cdk8s
examples/                               three worked values files
```

**`deployment/` is not cdk8s and holds no chart source.** It exists so that
lint, package and push are defined once, for CI and for a local run alike: a
`package.json` with three scripts, its lockfile, and `chart-lint.sh` — nothing
more. Do not convert this chart to cdk8s or any other synthesizer: a
synthesized chart flattens the conditionals that make the external-database,
OIDC and guacd paths configurable, and `values.yaml` is the point of the
chart.

## The one invariant that matters most

PatchMon resolves every setting as **environment > database > default**, and the
Settings UI edits the database layer. So a variable present in the pod spec
**pins that setting and greys the field out in the UI**.

That is why most entries under `server.env` are `null`, each with the
application's default in a comment beside it. Emitting them would take the
setting away from the operator. When adding a setting:

- optional, and settable in the UI → default it to `null`, comment the app default
- genuinely required in Kubernetes (`CORS_ORIGIN`, `TRUST_PROXY`, `PORT`,
  `DATABASE_URL`, the Redis endpoint, `GUACD_ADDRESS`, `POD_ID`) → set it

`null` and `""` are omitted from the pod; `false` and `0` are passed through,
because both are meaningful values. See `patchmon.server.envMap` in
`templates/_helpers.tpl` — a name/value-key pair there is all a simple setting
needs.

## Tracking a new PatchMon release

1. **The application's config loader is the authority, not its documentation.**
   The archived chart shipped `AUTO_CREATE_ROLE_PERMISSIONS` and
   `PM_LOG_TO_CONSOLE` long after 2.x stopped reading either.

   Run from the repository root:

   ```bash
   .claude/skills/patchmon-chart/scripts/check-env-drift.sh                 # clones PatchMon
   .claude/skills/patchmon-chart/scripts/check-env-drift.sh ~/src/PatchMon  # or reuse a checkout
   ```

   Read `DEAD` as actionable, `REVIEW` as needing a `grep` to confirm, and
   `NOT MODELLED` as expected for anything optional — see the invariant above.

2. Diff `docker/env.example` and `docker/docker-compose.yml` in the upstream
   repo. New dependencies show up there first: the `guacd` sidecar arrived that
   way in 2.0.

3. Bump `server.image.tag` in `values.yaml` and `appVersion` in `Chart.yaml`,
   together. Bump `version` per the scheme in `UPDATE.md`.

4. Check the dependency images. Upstream's compose file pins what they test
   against; this chart may sit a major ahead deliberately. A PostgreSQL major
   bump is a breaking change for existing deployments — `pg_upgrade` or
   dump/restore — so it belongs in a MAJOR chart bump with a README note.

5. Verify (see below), then commit on a feature branch and open a PR.

## Consumers

`values.yaml` is the chart's public interface. Renaming or removing a key is a
breaking change for anyone deploying it, so it belongs in a MAJOR chart bump
with the migration written down — `docs/upgrading-1x-to-2x.md` is the worked
example of doing that once already.

Two things that bite an existing release in particular, both covered under
Traps below: `fullnameOverride` renames volumes, and
`database.persistence.size` / `redis.persistence.size` are immutable once a
release exists, so they must keep whatever value the live PVCs were created
with.

## Verification

From the repository root:

```bash
(cd deployment && npm ci && npm run lint)        # what CI runs
python3 .claude/skills/patchmon-chart/scripts/check-values-refs.py
.claude/skills/patchmon-chart/scripts/check-env-drift.sh
```

`check-values-refs.py` exists because Helm renders a missing `.Values` path as
an empty string: a typo produces a chart that lints, templates, installs, and
silently drops the setting.

Render the combinations that only appear when something is switched on — HPA,
PDB, external services, the `fixPermissions` init containers, OIDC — not just
the defaults. Then validate against real Kubernetes schemas, which `helm lint`
does not do:

```bash
helm template patchmon . -f examples/values-external-services.yaml \
  | kubeconform -strict -summary -kubernetes-version 1.30.0 -
```

`kubeconform` runs in `lint.yml` only. It is deliberately not part of
`npm run lint`, so packaging never depends on the binary being present.

## Traps

Every one of these has already bitten this chart or its ancestor.

**`/health` is a dependency check, not a liveness check.** It answers 503 while
PostgreSQL or Redis is unreachable. On a liveness probe, a 30-second database
restart fails liveness on every replica at once and restarts them all — a blip
becomes an outage. Liveness is `tcpSocket`; `/health` drives readiness and the
startup probe. Do not "simplify" them to match.

**The httpGet probes must send `Host: localhost`.** PatchMon's CORS middleware
enforces the Host header, not just Origin, and answers
`403 {"code":"host_mismatch"}` for any Host that is neither loopback nor built
from `CORS_ORIGIN` (`internal/middleware/cors.go`). The kubelet sends the pod
IP, so without the header the startup probe fails, the container is killed
when the budget runs out, and the pod crashloops — while traffic through the
ingress is fine, which makes it look like a probe misconfiguration. Upstream
never sees it: their compose health check runs inside the container against
localhost. The header lives in `patchmon.server.probeAction`, which the
startup probe also goes through; do not inline an `httpGet` block that skips
it. Kubernetes' own `httpGet.host` field is the wrong fix — it points the
kubelet at the node's loopback, not the pod's.

**`.helmignore` leaks.** `deployment/`, `.github/` and `.claude/` are excluded
for a reason: CI wiring, local tooling and anything that may hold credentials
(an `.npmrc` in `deployment/`, for instance) have no business inside a package
handed to operators. This file has been broken twice by rewriting it rather
than editing it. After any change:

```bash
cd deployment && npm run build:helm -- --chart-version=0.0.0-dev
tar -tzf dist/patchmon-0.0.0-dev.tgz | grep -v '^patchmon/templates/'
```

Expect only `Chart.yaml`, `values.yaml`, `.helmignore`, `LICENSE`, `NOTICE`,
`README.md`, `UPDATE.md`.

**`fullnameOverride` renames volumes.** It feeds the StatefulSet
`volumeClaimTemplate` names, so changing it makes the pods claim new empty PVCs
while the old ones sit unreferenced. Treat a change to its default as breaking,
and check `kubectl get pvc` before advising anyone to upgrade.

**StatefulSet selectors and `podManagementPolicy` are immutable.** The selector
keeps a bare `app:` label for compatibility with the archived chart, so an
in-place `helm upgrade` from it works. `podManagementPolicy` defaults to
`OrderedReady` because that is what the archived chart produced — setting
`Parallel` is rejected by the API server on an existing StatefulSet.

**`publish` has no default registry.** `CHART_REGISTRY` must be set or the
script fails, on purpose — a default would make a mistyped or missing
environment push the chart somewhere nobody intended. `release.yml` sets it to
GHCR.

**Chart version and `appVersion` are independent.** `appVersion` tracks
PatchMon; the chart version says what an upgrade costs the operator. Do not
align them — `UPDATE.md` records why, and the archived chart's own release
history shows the alignment failing in practice.

**`helm package --version` validates SemVer.** Anything that is not a valid
SemVer string fails packaging outright. Release from tags, whose names are
`v<semver>`.

**Never generate secrets in the chart.** A value that changed on each
`helm upgrade` would invalidate every session and make every encrypted column
unreadable. The chart fails to render without them, on purpose, and
`patchmon.validateValues` says which one is missing.

## Releasing

`UPDATE.md` has the full matrix. In short: a release is a tag on `main`.

```bash
git tag v2.0.1 && git push origin v2.0.1
```

That publishes to `ghcr.io/<owner>/charts` and to the `helm` branch
(`release.yml`). GitHub Pages serves the `helm` branch at its root — that
branch name is the repository's actual Pages configuration, not a free choice.

Never tag from a feature branch: a chart version in an OCI registry is
effectively permanent.

## Working in this repo

- Feature branch always, never commit to `main` (org policy).
- `origin` is SSH. Over HTTPS, pushing anything under `.github/workflows/`
  fails — the `gh` OAuth token has no `workflow` scope.
- This repository is public. Nothing here should name internal hosts,
  registries, clusters, vaults or deployment repositories; keep examples
  generic (`example.com`, `<owner>`, `<namespace>`).
