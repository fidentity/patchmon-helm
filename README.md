# PatchMon Helm chart

> **Disclaimer — this is not an official PatchMon project.** It is an
> independent, community-maintained Helm chart, not affiliated with, endorsed
> by or supported by the PatchMon project or its maintainers. It packages
> upstream's images; it is not built by them. Open chart issues here, and
> application issues at
> [PatchMon/PatchMon](https://github.com/PatchMon/PatchMon).
>
> Derived from an archived community chart and distributed under GPL-3.0 — see
> [Provenance and licence](#provenance-and-licence).

A Helm chart for [PatchMon](https://github.com/PatchMon/PatchMon) 2.x — Linux
and Windows patch monitoring, compliance scanning and patch automation.

Chart `2.0.1` · PatchMon `v2.1.3` · Kubernetes 1.23+ · Helm 3.8+

> **Coming from a 1.4.x chart?** Read
> [docs/upgrading-1x-to-2x.md](docs/upgrading-1x-to-2x.md) first. PatchMon 2.0
> merged the backend and frontend into one Go binary and this chart's values
> changed with it — the upgrade is not a version bump.

## What it deploys

| Component | Kind | Purpose |
|---|---|---|
| `patchmon-server` | StatefulSet | The whole application: `/api/*` and the embedded React SPA on port 3000. Migrations run at boot. |
| `postgres` | StatefulSet | Bundled single-node PostgreSQL. Disable it to use your own. |
| `redis` | StatefulSet | Asynq job queues, bootstrap tokens, TFA lockout state, cross-pod agent presence. Not optional. |
| `guacd` | Deployment | Apache Guacamole daemon, for in-browser RDP to Windows hosts. Optional. |

The server needs no persistent volume: agent binaries and the SCAP compliance
content ship read-only in the image, and branding assets live in the database.

A StatefulSet rather than a Deployment, because each pod's stable hostname is
what the agent presence registry keys on.

## Install

The chart is published to two places, both carrying the same version built
from the same tag:

```bash
# GHCR, as an OCI chart
helm install patchmon oci://ghcr.io/fidentity/charts/patchmon --version 2.0.1

# classic repository, for tooling without OCI support
helm repo add patchmon https://fidentity.github.io/patchmon-helm
helm install patchmon patchmon/patchmon --version 2.0.1
```

The examples below use the OCI reference; swap it for `patchmon/patchmon` if
you added the classic repository.

The chart generates no secrets — a value that changed on every `helm upgrade`
would invalidate every session and make every encrypted column unreadable — so
four of them have to be supplied.

```bash
helm install patchmon oci://ghcr.io/fidentity/charts/patchmon \
  --namespace patchmon --create-namespace \
  --set server.env.serverHost=patchmon.example.com \
  --set server.env.serverProtocol=https \
  --set server.jwtSecret="$(openssl rand -hex 64)" \
  --set server.aiEncryptionKey="$(openssl rand -hex 64)" \
  --set database.auth.password="$(openssl rand -hex 32)" \
  --set redis.auth.password="$(openssl rand -hex 32)"
```

For anything real, put them in a Secret instead and reference it — see
[examples/values-prod.yaml](examples/values-prod.yaml):

```bash
kubectl create namespace patchmon
kubectl create secret generic patchmon-secrets -n patchmon \
  --from-literal=postgres-password="$(openssl rand -hex 32)" \
  --from-literal=redis-password="$(openssl rand -hex 32)" \
  --from-literal=jwt-secret="$(openssl rand -hex 64)" \
  --from-literal=ai-encryption-key="$(openssl rand -hex 64)" \
  --from-literal=session-secret="$(openssl rand -hex 64)"

helm install patchmon oci://ghcr.io/fidentity/charts/patchmon \
  -n patchmon -f examples/values-prod.yaml
```

Use [SOPS](https://github.com/getsops/sops),
[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) or
[External Secrets](https://external-secrets.io/) to keep that Secret in git.

| Secret | Required | Losing or changing it means |
|---|---|---|
| `jwt-secret` | yes | every session is invalidated |
| `ai-encryption-key` | yes | AI credentials, agent bootstrap tokens and notification secrets become unreadable |
| `postgres-password` | yes | — |
| `redis-password` | yes | — |
| `session-secret` | no | fallback encryption key, used only when `ai-encryption-key` is unset |
| `oidc-client-secret` | with OIDC | SSO stops working |

### Then set the Server URL

Log in, create the admin account, and set **Settings → Server URL** to the
address your hosts reach PatchMon on.

PatchMon 2.x keeps that URL in the database, where it defaults to
`http://localhost:3000`, and it is the address baked into every agent install
command. `server.env.serverHost` and friends configure this chart's derived
CORS origin and OIDC URIs — they do not set it. Until you do, the install
commands PatchMon hands out will not resolve for your hosts.

## Configuration

### The `server.env` model

PatchMon resolves each setting as **environment > database > default**, and the
Settings UI edits the database layer. A variable present in the pod spec
therefore pins that setting and greys the field out in the UI.

So most entries under `server.env` default to `null`, with the application's
default recorded in a comment beside them. Set one only when you want the chart
to own it; `false` and `0` are passed through, `null` and `""` are omitted from
the pod entirely.

For a variable this chart does not model — `ENABLE_PPROF`, the multi-tenant
`ADMIN_MODE` family, anything added after this chart was last updated — use
`server.extraEnv`, which takes the full container env syntax including
`valueFrom`, or `server.extraEnvFrom` to pull in a whole ConfigMap or Secret.

### Values reference

Only the values you are likely to change are listed. `values.yaml` is
commented throughout and is the complete reference.

#### Global

| Value | Description | Default |
|---|---|---|
| `global.imageRegistry` | Registry for every image, for air-gapped mirrors. Overrides per-component registries. | `""` |
| `global.imageTag` | Overrides `server.image.tag` only. | `""` |
| `global.imagePullSecrets` | Pull secrets for every pod. | `[]` |
| `global.storageClass` | StorageClass for every PVC. Overrides per-component. | `""` |
| `fullnameOverride` | Resource name prefix. **See the warning below.** | `""` |
| `commonLabels` / `commonAnnotations` | Applied to every resource. | `{}` |

#### Server

| Value | Description | Default |
|---|---|---|
| `server.image.tag` | PatchMon version. | `2.1.3` |
| `server.replicaCount` | Replicas. More than 1 needs ingress sticky sessions. | `1` |
| `server.containerPort` | Port inside the container (`PORT`). | `3000` |
| `server.env.serverProtocol` / `serverHost` / `serverPort` | The public URL, used to derive the CORS origin and the OIDC URIs. | `http` / `patchmon.example.com` / `""` |
| `server.env.corsOrigin` | Override the derived origin. Comma-separate for several, no spaces. | `""` (derived) |
| `server.env.trustProxy` | Trust `X-Forwarded-*`. Needed behind an ingress. | `true` |
| `server.env.trustedProxyRanges` | CIDRs of chained proxies. Leave empty for a single ingress. | `""` |
| `server.env.enableHsts` | Send `Strict-Transport-Security`. | `false` |
| `server.env.timezone` | `TZ` for logs and scheduled jobs. | `UTC` |
| `server.jwtSecret` / `aiEncryptionKey` / `sessionSecret` | See the secrets table. | `""` |
| `server.existingSecret` | Read all three from this Secret instead. | `""` |
| `server.autoscaling.enabled` | HPA over the StatefulSet. | `false` |
| `server.podDisruptionBudget.enabled` | PDB. Only useful above one replica. | `false` |
| `server.extraEnv` / `extraEnvFrom` | Extra environment, full container syntax. | `[]` |
| `server.extraVolumes` / `extraVolumeMounts` | For private CAs and the like. | `[]` |

#### Database

| Value | Description | Default |
|---|---|---|
| `database.enabled` | Deploy the bundled PostgreSQL. | `true` |
| `database.image.tag` | PostgreSQL version. | `18-alpine` |
| `database.auth.database` / `.username` / `.password` | Credentials, for bundled and external alike. | `patchmon_db` / `patchmon_user` / `""` |
| `database.auth.existingSecret` | Read the password from this Secret. | `""` |
| `database.external.host` / `.port` | Required when `enabled` is false. | `""` / `5432` |
| `database.external.sslMode` | `disable`…`verify-full`. Applied to external only. | `require` |
| `database.external.extraParams` | Extra libpq parameters for `DATABASE_URL`. | `""` |
| `database.persistence.size` | PVC size. Immutable after install — see below. | `5Gi` |

#### Redis

| Value | Description | Default |
|---|---|---|
| `redis.enabled` | Deploy the bundled Redis. | `true` |
| `redis.image.tag` | Redis version. | `8-alpine` |
| `redis.auth.password` / `.existingSecret` | Required either way. | `""` |
| `redis.external.host` / `.port` / `.username` | Required when `enabled` is false. | `""` / `6379` / `""` |
| `redis.external.tls.enabled` / `.verify` / `.caFile` | TLS to an external Redis. | `false` / `true` / `""` |
| `redis.extraFlags` | Extra `redis-server` arguments, one token per entry. | `["--appendonly","yes"]` |
| `redis.persistence.size` | PVC size. Immutable after install — see below. | `5Gi` |

#### guacd, ingress, service account

| Value | Description | Default |
|---|---|---|
| `guacd.enabled` | Deploy guacd. Only in-browser RDP needs it. | `true` |
| `guacd.image.tag` | guacd version. | `1.6.0` |
| `guacd.externalAddress` | `host:port` of a guacd elsewhere, when `enabled` is false. | `""` |
| `ingress.enabled` | Create an Ingress. | `false` |
| `ingress.className` / `.annotations` / `.hosts` / `.tls` | Standard. Defaults carry the nginx websocket timeouts. | see `values.yaml` |
| `serviceAccount.create` | Create a ServiceAccount. No RBAC is needed. | `true` |
| `secret.create` | Render the chart's Secret. Set false when everything is external. | `true` |
| `rollOnConfigChange` | Roll the server pods when the ConfigMap or Secret changes. | `true` |

### `fullnameOverride` and your volumes

`fullnameOverride` feeds the StatefulSet volumeClaimTemplate names, so changing
it — including changing it *away from* the `patchmon-prod` default that the
1.4.x chart shipped — makes the pods claim new, empty volumes while the old
PVCs sit unreferenced. Check `kubectl get pvc` before your first upgrade and
set it to match.

### Volume sizes are fixed at install time

`database.persistence.size` and `redis.persistence.size` feed the StatefulSet
`volumeClaimTemplates`, which Kubernetes will not let you change. Setting a
different value on an existing release makes `helm upgrade` fail:

```
updates to statefulset spec for fields other than 'replicas', 'ordinals',
'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy' and
'minReadySeconds' are forbidden
```

Pick the size at install time. To grow one later, expand the PVC itself (if the
StorageClass allows it) and then delete the StatefulSet with
`--cascade=orphan` so the next upgrade recreates it against the existing
volume. The defaults match the chart this one descends from, so an in-place
upgrade from it needs no change here.

### External PostgreSQL and Redis

The bundled StatefulSets are single-node, with no backups, no replication and
no connection pooler. For production, point the chart at something managed —
[examples/values-external-services.yaml](examples/values-external-services.yaml):

```yaml
database:
  enabled: false
  external:
    host: postgres.patchmon.svc.cluster.local
    sslMode: verify-full
    extraParams: "sslrootcert=/etc/ssl/patchmon/pg-ca.crt"
  auth:
    database: patchmon
    username: patchmon
    existingSecret: patchmon-db-credentials
```

`DATABASE_URL` is assembled by the chart, with the password interpolated as
`$(POSTGRES_PASSWORD)` so it never appears in the rendered manifest.

### OIDC / SSO

```yaml
server:
  oidc:
    enabled: true
    issuerUrl: https://auth.example.com/application/o/patchmon/
    clientId: patchmon
    existingSecret: patchmon-secrets
    existingSecretClientSecretKey: oidc-client-secret
    scopes: "openid profile email offline_access groups"
    autoCreateUsers: true
    syncRoles: true
    groups:
      admin: patchmon-admins
      readonly: patchmon-viewers
```

The redirect URI is derived as
`<protocol>://<host>[:<port>]/api/v1/auth/oidc/callback` — register exactly
that with your provider, or set `server.oidc.redirectUri` explicitly if your
provider needs something else. `helm template` prints the value it will use.

`syncRoles` needs the `groups` scope to actually return group claims; some
providers only issue a refresh token when `offline_access` is requested, which
is why it is in the default scope list. `enforceHttps` is on by default and
should only be turned off for a local test deployment served over plain HTTP.

### Multiple replicas

Supported since PatchMon 2.0: there are no writeable local volumes, jobs are
coordinated through Redis and Asynq, and agent presence is shared over Redis
pub/sub keyed on `POD_ID`, which the chart sets from the pod name.

Agent connections, the browser SSH terminal, the RDP tunnel and live patch-run
logs are all websockets, so sticky sessions are required:

```yaml
server:
  replicaCount: 3
ingress:
  annotations:
    nginx.ingress.kubernetes.io/affinity: "cookie"
```

### Ingress and websockets

The default annotations raise the nginx proxy timeouts to 86400s. Without that,
agents show as "connecting" and drop every 30–60 seconds. The endpoints that
need it:

| Endpoint | Used by |
|---|---|
| `/api/v1/agents/ws` | the PatchMon agent |
| `/api/v1/ssh-terminal/{hostId}` | the browser SSH terminal |
| `/api/v1/rdp/websocket-tunnel` | browser RDP through guacd |
| `/api/v1/patching/runs/{id}/stream` | live patch-run logs |

Traefik proxies websockets without configuration. For other controllers,
translate the nginx annotations.

## Operating

### Probes

`GET /health` reports on PostgreSQL and Redis as well as the process, and
answers 503 while either is unreachable. The chart therefore uses it for the
startup and readiness probes but **not** for liveness — a 30-second database
restart on a `/health` liveness probe fails every replica at once and restarts
them all, turning a blip into an outage. Liveness only checks that the listener
accepts connections.

The startup probe's budget is 40 × 10s = 400s, which is what the first boot's
schema migrations get before Kubernetes gives up.

### Upgrading

```bash
helm upgrade patchmon oci://ghcr.io/fidentity/charts/patchmon \
  -n patchmon -f my-values.yaml --wait --timeout 15m
```

Migrations run automatically at boot and are not reversible, so `helm rollback`
restores the manifests but not the schema. Take a dump before a major upgrade:

```bash
kubectl exec -n patchmon patchmon-database-0 -- \
  pg_dump -U patchmon_user patchmon_db > patchmon-backup.sql
```

### Troubleshooting

```bash
# Where is it stuck?
kubectl get pods -n patchmon
kubectl describe pod -n patchmon <pod>

# Server logs, including the migrations
kubectl logs -n patchmon -l app.kubernetes.io/component=server --tail=200 -f

# Init containers, when a pod sits in Init:
kubectl logs -n patchmon <pod> -c wait-for-database
kubectl logs -n patchmon <pod> -c wait-for-redis

# What the server thinks its dependencies are doing
kubectl exec -n patchmon patchmon-server-0 -- \
  wget -qO- 'http://localhost:3000/health?format=json'
```

| Symptom | Likely cause |
|---|---|
| Pod stuck in `Init:0/3` | PostgreSQL, Redis or guacd not reachable; check the init container logs |
| Blank page after login, console CORS errors | `server.env.corsOrigin` does not match the browser's origin exactly |
| Agent install commands point at `localhost:3000` | Settings → Server URL was never set; see above |
| Agents drop every 30–60s | ingress websocket timeouts too low |
| Agents appear offline with several replicas | sticky sessions not enabled at the ingress |
| In-browser RDP fails to connect | `guacd.enabled` is false, or `guacd.externalAddress` is unset |
| PostgreSQL starts empty after an upgrade | `fullnameOverride` changed and the pods claimed new PVCs |
| `initdb: directory ... not empty` | the data volume was mounted without a `PGDATA` subdirectory; this chart sets it |
| A setting is greyed out in the UI | it is pinned by an environment variable; unset it in `server.env` |

### Uninstall

```bash
helm uninstall patchmon -n patchmon

# StatefulSet PVCs are deliberately not removed with the release.
kubectl get pvc -n patchmon
kubectl delete pvc -n patchmon -l app.kubernetes.io/instance=patchmon
```

## Development

```bash
# lint and render every example — the same script the build runs
cd deployment && npm run lint && cd ..

helm template patchmon . -f examples/values-prod.yaml

helm install pm . -n pm-test --create-namespace \
  -f examples/values-quick-start.yaml --wait --timeout 10m
helm test pm -n pm-test
```

The chart lives at the repository root as ordinary Helm templates.
`deployment/` holds only the npm scripts the GitHub workflows drive, so lint,
package and push are defined once; it is excluded from the package.

[UPDATE.md](UPDATE.md) covers tracking a new PatchMon release, the chart
version scheme, and how a tag is published to both registries.

## Provenance and licence

This is not an official PatchMon project — see the disclaimer at the top.

Derived from the community chart at
[RuTHlessBEat200/PatchMon-helm](https://github.com/RuTHlessBEat200/PatchMon-helm)
(archived) by way of a fork for PatchMon 1.4.2, and rewritten for 2.x. Licensed
GPL-3.0, as that chart is; see [LICENSE](LICENSE) and [NOTICE](NOTICE).

PatchMon itself is a separate work with its own licence:
<https://github.com/PatchMon/PatchMon>. Application docs:
<https://docs.patchmon.net>.
