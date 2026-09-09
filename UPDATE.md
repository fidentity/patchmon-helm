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

5. Lint and render every example:

   ```bash
   helm lint . --set server.jwtSecret=x --set server.aiEncryptionKey=y \
     --set database.auth.password=p --set redis.auth.password=r

   for f in examples/*.yaml; do
     echo "== $f"; helm template patchmon . -f "$f" >/dev/null || echo FAILED
   done
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

Two workflows publish the chart, and both derive the version from the tag, so
`Chart.yaml` in git does not have to carry the released number:

- `.github/workflows/release-pages.yml` — on push to `main`, packages the chart
  and publishes a classic Helm repository on the `gh-pages` branch.
- `.github/workflows/release-oci.yml` — on a `v*.*.*` tag, pushes to the GHCR
  OCI registry and creates a GitHub release.

```bash
git tag v2.0.1 && git push origin v2.0.1
```

Enable GitHub Pages for the `gh-pages` branch once, so the classic repository
is served.
