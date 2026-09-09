# Maintaining this chart

## Tracking a new PatchMon release

1. Read the upstream release notes for new, renamed or removed environment
   variables: <https://github.com/PatchMon/PatchMon/releases>.

   The authoritative list is the application's own config loader, not the
   documentation:

   ```bash
   git clone --depth 1 https://github.com/PatchMon/PatchMon /tmp/patchmon
   sed -n '/^func Load/,/^}/p' /tmp/patchmon/server-source-code/internal/config/config.go
   ```

   Compare it against `patchmon.server.envMap` in `templates/_helpers.tpl` and
   the `server.env` block in `values.yaml`. Anything the loader no longer reads
   should come out of the chart; a variable set in the pod spec that the
   application ignores is a silent lie in the values file.

   Also diff `docker/env.example` and `docker/docker-compose.yml`, which is
   where new dependencies (such as the `guacd` sidecar in 2.0) show up first.

2. Bump `server.image.tag` in `values.yaml` and `appVersion` in `Chart.yaml`
   to the new version. Keep them in step.

3. Bump `version` in `Chart.yaml` — see the scheme below.

4. Check the dependency images. PatchMon's compose file pins the versions
   upstream actually tests against; this chart may sit a major ahead. Changing
   the PostgreSQL major version is a breaking change for existing deployments
   (`pg_upgrade` or dump/restore), so it belongs in a MAJOR chart bump with a
   note in the README.

5. Lint and render every example — the same script CI runs:

   ```bash
   cd deployment && npm run lint
   ```

6. Install into a scratch namespace and check the rollout, then `helm test`:

   ```bash
   helm install pm . -n pm-test --create-namespace -f examples/values-quick-start.yaml --wait --timeout 10m
   helm test pm -n pm-test
   ```

## Chart version scheme

The chart version is independent of `appVersion` and follows semver in terms of
*what an operator has to do to upgrade*:

- **MAJOR** — the upgrade needs manual intervention: a values key was renamed
  or removed, a resource has to be deleted by hand, a PostgreSQL or Redis major
  version changed, or PVC layout changed.
- **MINOR** — a new PatchMon `appVersion`, new configuration options, new
  optional templates. `helm upgrade` is enough.
- **PATCH** — template fixes, documentation, resource and probe tuning. No
  `appVersion` change.

Examples: `2.0.0 -> 2.1.0` for PatchMon 2.1.3 -> 2.2.0; `2.0.0 -> 2.0.1` for a
probe fix; `2.0.0 -> 3.0.0` for PostgreSQL 18 -> 19.

## Releasing

The chart is built and published by TeamCity, following the same pattern as the
other fidentity service repositories: `.teamcity/settings.kts` composes the
shared Kotlin DSL from `fidentity/infrastructure` (`teamcity/teamcity-lib`).

There is no image build here — this repository ships only the chart — so the
`release` job depends on the `helm build` job alone, where a service repository
would also list its `docker build`.

### What the build does

`fityHelmBuildStep` runs in `deployment/` and drives npm, so the chart-specific
work lives in `deployment/package.json`:

| npm script | What it does |
|---|---|
| `prebuild:helm` | `helm lint` and renders every example (`deployment/chart-lint.sh`) |
| `build:helm` | `helm package .. --version <chart-version> --destination dist` |
| `publish` | `helm push dist/<tgz> oci://hub.fity.tech/fidentity-charts` |

The chart itself stays at the repository root as ordinary Helm templates;
`deployment/` exists only because the shared build step's working directory is
fixed. `deployment/` and `.teamcity/` are in `.helmignore`, so neither ends up
inside the package — which matters, because the build step writes an `.npmrc`
carrying a registry token into that directory.

### Versions

The chart version comes from `fityGoRetagStep`, not from `Chart.yaml`:
`helm package --version` overrides it at build time. `appVersion` is *not*
overridden and stays hand-maintained in `Chart.yaml`, because the chart and
PatchMon move independently.

Each build publishes twice — once under `%image.version%` and once under
`%image.tag%`:

| Branch or tag | `image.version` (immutable) | `image.tag` (moving) |
|---|---|---|
| `main` | `0.0.<build>-dev` | `0.0.0-dev` |
| feature branch / PR | `0.0.<build>-dev-<branch>` | `0.0.0-dev-<branch>` |
| tag `v2.0.1` | `2.0.1` | `2.0.1` |

So a release is a git tag:

```bash
git tag v2.0.1 && git push origin v2.0.1
```

One caveat inherited from the shared step: `helm package --version` validates
SemVer. A `release_x.y` branch resolves `image.tag` to `release-x.y`, which is
not valid SemVer and will fail the second publish. Release from tags.

### Installing a published chart

```bash
helm registry login hub.fity.tech
helm install patchmon oci://hub.fity.tech/fidentity-charts/patchmon \
  --version 2.0.1 -n patchmon --create-namespace -f my-values.yaml
```

### Running the same checks locally

```bash
cd deployment
npm run lint                                  # what prebuild:helm runs in CI
npm run build:helm -- --chart-version=0.0.0-dev
```

`kubeconform` is not in the build image, so schema validation is a local step:

```bash
helm template patchmon . -f examples/values-prod.yaml \
  | kubeconform -strict -summary -kubernetes-version 1.30.0 -
```
