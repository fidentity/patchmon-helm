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

A release is a **git tag**. Two registries are published from one definition:

| Target | For |
|---|---|
| `oci://ghcr.io/fidentity/charts` | OCI consumers |
| `https://fidentity.github.io/patchmon-helm` | `helm repo add`, for tools without OCI support |

```bash
git tag v2.0.1 && git push origin v2.0.1
```

Only tags are published; branch builds lint but do not publish.

### One definition

The lint, package and push logic lives in `deployment/package.json`, so the
workflows and a local run cannot drift:

| npm script | What it does |
|---|---|
| `lint` | `helm lint` and renders every example (`deployment/chart-lint.sh`) |
| `prebuild:helm` | runs `lint`, so a chart that does not render never reaches a registry |
| `build:helm` | `helm package .. --version <chart-version> --destination dist` |
| `publish` | `helm push dist/<tgz> "$CHART_REGISTRY"` |

`publish` has no default registry on purpose: `CHART_REGISTRY` must be set, or
the script fails rather than guessing where to push. `release.yml` sets it to
GHCR.

The chart itself stays at the repository root as ordinary Helm templates;
`deployment/` holds only the npm scripts, its lockfile and `chart-lint.sh`. It
is in `.helmignore`, so it never ends up inside the package.

### GitHub Actions

| Workflow | Trigger | Does |
|---|---|---|
| `lint.yml` | push to `main`, pull requests | `npm run lint`, plus `kubeconform` schema validation |
| `release.yml` | tag `v*.*.*`, or manual dispatch | packages, pushes to GHCR, rebuilds the Pages index, creates a GitHub release |

`kubeconform` runs only in `lint.yml`, so that packaging does not depend on a
kubeconform binary being present.

A manual dispatch takes a version and checks out `v<version>`, not the branch
it was started from, so re-publishing after a registry failure cannot put a
different tree under an existing version.

The classic repository is served by GitHub Pages from the **`helm` branch at
its root** — already configured, so the branch name in `release.yml` is not a
free choice. The workflow copies the new package onto that branch, rebuilds
`index.yaml` from the packages present and re-renders `index.html`; it leaves
other files there alone.

### The landing page

The repository URL answers in a browser as well as to `helm repo add`, from an
`index.html` on the `helm` branch next to `index.yaml`.

It is **generated, not hand-edited**. The template is
`deployment/pages/index.html` on `main`, and the release workflow renders it
onto the branch, substituting two placeholders:

| Placeholder | Comes from |
|---|---|
| `@@CHART_VERSION@@` | the version being published, the tag with `v` stripped |
| `@@APP_VERSION@@` | `appVersion` read back out of the packaged `.tgz` |

Read out of the package rather than out of the working tree, so the page cannot
advertise an `appVersion` that is not the one inside the chart people download.
A placeholder left unsubstituted — a renamed token, a typo — fails the release
rather than publishing `@@…@@` to the site.

Editing the page is therefore an ordinary change to `main`. It goes live at the
next release; to publish it sooner, dispatch `release.yml` with the version
already released. That re-runs a reproducible package, so the only thing that
changes is the page.

Anything else on the page that could go stale — the Kubernetes and Helm floors
in the version chips, the README anchors it links to — is not substituted.
Check those when `kubeVersion` in `Chart.yaml` changes or a README heading is
renamed.

### Versions

The chart version comes from the build, not from `Chart.yaml`:
`helm package --version` overrides it, using the tag with the leading `v`
stripped. `appVersion` is *not* overridden and stays hand-maintained in
`Chart.yaml`, because the chart and PatchMon move independently.

So on `v2.0.1` both registries carry `2.0.1` built from the same tree. Keep
`Chart.yaml`'s `version` in step with the tag you intend to push anyway — it is
what anyone reading the repository sees.

`helm package --version` validates SemVer, so the version passed in has to be
a valid SemVer string. Release from tags.

### Installing a published chart

```bash
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
npm run lint                                   # what CI runs
npm run build:helm -- --chart-version=0.0.0-dev
```

Schema validation, which only `lint.yml` runs:

```bash
helm template patchmon . -f examples/values-prod.yaml \
  | kubeconform -strict -summary -kubernetes-version 1.30.0 -
```
