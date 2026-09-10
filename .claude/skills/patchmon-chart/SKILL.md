---
name: patchmon-chart
description: Maintain, verify or release the PatchMon Helm chart in this repository — tracking a new upstream PatchMon version, adding or changing values, debugging what the chart renders, or publishing it. Also covers how the chart is consumed by infrastructure-apps/apps/patchmon. Use whenever work touches Chart.yaml, values.yaml, templates/, deployment/, the CI that publishes the chart, or the values that deployment repo passes in.
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
| `~/fidentity/infrastructure-apps/apps/patchmon` | the only consumer — what actually gets deployed, and with which values |

## Repository shape

```
Chart.yaml  values.yaml  templates/     the chart, plain Helm
deployment/                             npm build wrapper — NOT cdk8s
.teamcity/                              TeamCity Kotlin DSL
examples/                               three worked values files
```

**`deployment/` is not cdk8s.** The sibling fidentity service repos synthesize
their charts from TypeScript in `deployment/`; this one does not. The directory
exists only because the shared TeamCity step `fityHelmBuildStep` has its working
directory fixed at `./deployment` and drives npm. It holds a `package.json`
with three scripts, its lockfile, and `chart-lint.sh` — nothing more. Do not
convert this chart to cdk8s: a synthesized chart flattens
the conditionals that make the external-database, OIDC and guacd paths
configurable, and `values.yaml` is the point of the chart.

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

## The consumer: infrastructure-apps

The chart is deployed by **`~/fidentity/infrastructure-apps/apps/patchmon`**,
which is cdk8s TypeScript synthesizing an ArgoCD Application. Read it before
changing anything in `values.yaml`: it is the only known consumer, so a values
rename is a breaking change to that repo specifically.

| File | Holds |
|---|---|
| `main.ts` | the live instance — domain, chart version, secret names, external database |
| `components/helm.ts` | the `Helm` construct and the whole values block |
| `components/secrets.ts` | ExternalSecret pulling from the `k8s-services-infra` vault |
| `components/ingress-components.ts` | Traefik middlewares, IP allowlist |
| `components/compliance-prune-cronjob.ts` | raw-SQL prune of `compliance_scans` / `compliance_results` |
| `types/patchmon.ts` | the props interface mirroring the values it sets |

Live shape as of chart 2.0.1:

- `sentinel.infra.fity.tech`, ArgoCD project `fity-apps`, namespace
  `fity-apps-patchmon-main`, `fullnameOverride: patchmon-main`
- **external PostgreSQL on Aiven**, `database.external.sslMode: require` —
  this is why the 1.4.2 fork grew external-database support in the first place
- **bundled Redis**, storage class `fity-nfs`, `persistence.size` pinned to
  `5Gi`. That is what the live PVC was created with and a
  `volumeClaimTemplate` is immutable, so any other value fails the upgrade
  outright — do not "tidy" it to a smaller number
- **guacd enabled**, for in-browser RDP to Windows hosts
- `secret.create: false` — every credential comes from the ExternalSecret
- images from the `hub.fity.tech/k8s-cache-*` mirrors, set per component
  through `image.registry` rather than `global.imageRegistry`
- Traefik, not ingress-nginx, so the chart's default nginx timeout annotations
  do not apply — the middlewares carry that
- OIDC against Zitadel with `disableLocalAuth: true` and `patchmon_*` groups
- secret keys use **underscores** (`jwt_secret`, `ai_encryption_key`,
  `postgres_password`, `redis_password`, `oidc_client_secret`), overridden via
  the `existingSecret*Key` values

The compliance prune CronJob lives there rather than in the chart on purpose:
it is an operational workaround for unbounded compliance-table growth, and it
runs `DELETE` against the production database. Never run it by hand.

The move from the 1.4.x values shape landed in infrastructure-apps#26 (chart
2.0.0) and #27 (2.0.1); `docs/upgrading-1x-to-2x.md` records what that
migration involved. That repository is a separate change in a separate
repository — do not edit it from here without being asked.

## Verification

From the repository root:

```bash
(cd deployment && npm ci && npm run lint)        # what both CI systems run
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

`kubeconform` runs in `lint.yml` but not in TeamCity, which has no such binary
in its helm image.

## Traps

Every one of these has already bitten this chart or its ancestor.

**`/health` is a dependency check, not a liveness check.** It answers 503 while
PostgreSQL or Redis is unreachable. On a liveness probe, a 30-second database
restart fails liveness on every replica at once and restarts them all — a blip
becomes an outage. Liveness is `tcpSocket`; `/health` drives readiness and the
startup probe. Do not "simplify" them to match.

**`.helmignore` leaks.** `deployment/`, `.teamcity/`, `.github/` and `.claude/`
are excluded for a reason — `fityHelmBuildStep` writes an `.npmrc` carrying a
registry token into `deployment/`. This file has been broken twice by rewriting
it rather than editing it. After any change:

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

**`CHART_REGISTRY`'s default is load-bearing.** `fityHelmBuildStep` is fixed and
cannot pass environment, so unset must mean `hub.fity.tech`. Changing that
default in `deployment/package.json` silently redirects the TeamCity publish.

**Chart version and `appVersion` are independent.** `appVersion` tracks
PatchMon; the chart version says what an upgrade costs the operator. Do not
align them — `UPDATE.md` records why, and the archived chart's own release
history shows the alignment failing in practice.

**`helm package --version` validates SemVer.** A `release_x.y` branch resolves
`image.tag` to `release-x.y`, which is not valid SemVer and fails the second
TeamCity publish. Release from tags.

**Never generate secrets in the chart.** A value that changed on each
`helm upgrade` would invalidate every session and make every encrypted column
unreadable. The chart fails to render without them, on purpose, and
`patchmon.validateValues` says which one is missing.

## Releasing

`UPDATE.md` has the full matrix. In short: a release is a tag on `main`.

```bash
git tag v2.0.1 && git push origin v2.0.1
```

That publishes to `ghcr.io/fidentity/charts` and the `helm` branch (GitHub
Actions, `release.yml`) and to `hub.fity.tech/fidentity-charts` (TeamCity).
GitHub Pages serves the `helm` branch at its root — that branch name is the
repository's actual Pages configuration, not a free choice.

Never tag from a feature branch: a chart version in an OCI registry is
effectively permanent.

## Working in this repo

- Feature branch always, never commit to `main` (org policy).
- `origin` is SSH. Over HTTPS, pushing anything under `.github/workflows/`
  fails — the `gh` OAuth token has no `workflow` scope.
- The Kotlin DSL in `.teamcity/` cannot be compiled locally: maven and the
  private `teamcity-lib` artifact are not available. Validate it by comparing
  against a sibling repo (`~/fidentity/infra-auth-service/.teamcity/`) and let
  the first TeamCity run be the real test.
