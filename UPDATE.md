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

A release is a **git tag**. Three registries are published from one definition,
by two drivers:

| Target | Driven by | For |
|---|---|---|
| `oci://hub.fity.tech/fidentity-charts` | TeamCity | internal cluster pulls |
| `oci://ghcr.io/fidentity/charts` | GitHub Actions | OCI consumers outside the cluster |
| `https://fidentity.github.io/patchmon-helm` | GitHub Actions | `helm repo add`, for tools without OCI support |

```bash
git tag v2.0.1 && git push origin v2.0.1
```

TeamCity additionally publishes development versions on every branch; GitHub
Actions only publishes tags. See the version table below.

### One definition, two drivers

The lint, package and push logic lives in `deployment/package.json`. Both
TeamCity's `fityHelmBuildStep` and the GitHub workflows call the same scripts,
so the two cannot drift:

| npm script | What it does |
|---|---|
| `lint` | `helm lint` and renders every example (`deployment/chart-lint.sh`) |
| `prebuild:helm` | runs `lint`, so a chart that does not render never reaches a registry |
| `build:helm` | `helm package .. --version <chart-version> --destination dist` |
| `publish` | `helm push dist/<tgz> "${CHART_REGISTRY:-oci://hub.fity.tech/fidentity-charts}"` |

Only the registry differs, through `CHART_REGISTRY`. Unset — which is how
TeamCity invokes it, since `fityHelmBuildStep` is fixed and cannot pass
environment — it defaults to `hub.fity.tech`. The GitHub workflow sets it to
GHCR. **Keep that default:** changing it silently redirects the TeamCity
publish.

The chart itself stays at the repository root as ordinary Helm templates;
`deployment/` exists only because the shared TeamCity step's working directory
is fixed at `./deployment`. Both `deployment/` and `.teamcity/` are in
`.helmignore`, so neither ends up inside the package — which matters, because
`fityHelmBuildStep` writes an `.npmrc` carrying a registry token there.

### TeamCity

`.teamcity/settings.kts` composes the shared Kotlin DSL from
`fidentity/infrastructure` (`teamcity/teamcity-lib`), the same as the other
service repositories. There is no image build here — this repository ships only
the chart — so the `release` job depends on the `helm build` job alone, where a
service repository would also list its `docker build`.

### GitHub Actions

| Workflow | Trigger | Does |
|---|---|---|
| `lint.yml` | push to `main`, pull requests | `npm run lint`, plus `kubeconform` schema validation |
| `release.yml` | tag `v*.*.*`, or manual dispatch | packages, pushes to GHCR, rebuilds the gh-pages index, creates a GitHub release |

`lint.yml` overlaps with TeamCity, which lints in `prebuild:helm` and reports
through GitHub Checks. It is the same `npm run lint` rather than a second set of
checks, and it covers forks and the period before the TeamCity project exists.

`kubeconform` runs only here, because it is not in the TeamCity helm build
image.

A manual dispatch takes a version and checks out `v<version>`, not the branch
it was started from, so re-publishing after a registry failure cannot put a
different tree under an existing version.

**One-time setup:** enable GitHub Pages for the `gh-pages` branch under
Settings → Pages. The workflow creates the branch on its first run.

### Versions

The chart version comes from the build, not from `Chart.yaml`:
`helm package --version` overrides it. `appVersion` is *not* overridden and
stays hand-maintained in `Chart.yaml`, because the chart and PatchMon move
independently.

TeamCity gets its version from `fityGoRetagStep` and publishes twice, under an
immutable and a moving version:

| Branch or tag | `image.version` (immutable) | `image.tag` (moving) |
|---|---|---|
| `main` | `0.0.<build>-dev` | `0.0.0-dev` |
| feature branch / PR | `0.0.<build>-dev-<branch>` | `0.0.0-dev-<branch>` |
| tag `v2.0.1` | `2.0.1` | `2.0.1` |

GitHub Actions uses the tag alone, so on `v2.0.1` all three registries carry
`2.0.1` built from the same tree.

One caveat inherited from the shared TeamCity step: `helm package --version`
validates SemVer. A `release_x.y` branch resolves `image.tag` to `release-x.y`,
which is not valid SemVer and fails the second publish. Release from tags.

### Installing a published chart

```bash
# internal
helm registry login hub.fity.tech
helm install patchmon oci://hub.fity.tech/fidentity-charts/patchmon --version 2.0.1

# GHCR
helm install patchmon oci://ghcr.io/fidentity/charts/patchmon --version 2.0.1

# classic repository
helm repo add patchmon https://fidentity.github.io/patchmon-helm
helm install patchmon patchmon/patchmon --version 2.0.1
```

### Running the same checks locally

```bash
cd deployment
npm ci
npm run lint                                   # what both CI systems run
npm run build:helm -- --chart-version=0.0.0-dev
```

Schema validation, which only `lint.yml` runs:

```bash
helm template patchmon . -f examples/values-prod.yaml \
  | kubeconform -strict -summary -kubernetes-version 1.30.0 -
```
