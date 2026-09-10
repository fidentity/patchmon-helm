# Upgrading from a PatchMon 1.4.x chart to this one

**This is not a drop-in upgrade.** PatchMon 2.0 replaced the Node.js stack with
a single Go binary, and this chart's values changed with it. Bumping the chart
version without reading this page will leave you with a broken release — and,
in one specific case described below, with orphaned volumes.

Upstream's own notes: <https://docs.patchmon.net/books/patchmon-application-documentation/page/migrating-from-142-to-200>

## What changed in the application

| Concept | 1.4.x (Node.js) | 2.x (Go) |
|---|---|---|
| Containers | `patchmon-backend` + `patchmon-frontend` | one `patchmon-server` |
| Listen ports | backend 3001, frontend 3000 | server 3000 serves `/api/*` and the SPA |
| Migrations | Prisma, separate step | golang-migrate, embedded, automatic at boot |
| Job queue | BullMQ | Asynq (still on Redis) |
| Agent binaries | written to a PVC | baked into the image, read-only |
| Branding assets | assets volume | stored in the database |
| Windows RDP | not available | `guacd` pod (optional) |

Two consequences worth stating plainly: the agent-files PVC is now dead weight,
and the server no longer needs a writeable volume at all.

## What changed in the chart

| 1.4.x chart | This chart |
|---|---|
| `backend.*` | `server.*` |
| `frontend.*` | removed — delete the block |
| `backend.persistence.*` | removed — no PVC is needed |
| `backend.env.trustProxy: "10.0.0.0/8,..."` | `server.env.trustProxy: true` plus `server.env.trustedProxyRanges` for the CIDR list |
| `backend.env.autoCreateRolePermissions` | removed — the variable no longer exists in 2.x |
| `database.auth.customHost` / `customPort` / `ssl` | `database.external.host` / `.port` / `.sslMode` |
| ingress `/` to frontend:3000 and `/api` to backend:3001 | a single `/` to `server:3000` |
| — | `guacd.*` (new) |
| — | `server.sessionSecret` (new, optional) |
| `ingress.enabled: true` by default | `false` by default — set it explicitly |
| `fullnameOverride: "patchmon-prod"` by default | `""` by default — **see step 1** |

Settings such as rate limits and the database pool are no longer written into
the pod by default. PatchMon resolves each setting as
`environment > database > default`, so a variable set in the pod spec is
**read-only in the Settings UI**. This chart therefore leaves them `null` and
lets the UI own them. Set them in `server.env` only when you want the chart to
be the source of truth.

## Migration steps

### 1. Check `fullnameOverride` first

The 1.4.x chart shipped `fullnameOverride: "patchmon-prod"` as its *default*.
This chart's default is `""`, which derives names from the release name.

The name is part of the StatefulSet volumeClaimTemplate names, so if your old
release relied on that default and you upgrade without setting it, PostgreSQL
and Redis come up against **brand new, empty volumes** while the old PVCs sit
unreferenced. The database is not deleted, but PatchMon will look empty.

    # Find out what your existing resources are called:
    kubectl get pvc -n <namespace>

    # If they are named postgres-data-patchmon-prod-database-0, then set:
    fullnameOverride: "patchmon-prod"

### 1b. Keep the volume sizes you already have

`database.persistence.size` and `redis.persistence.size` feed the StatefulSet
`volumeClaimTemplates`, which are immutable — an upgrade that changes them is
rejected outright:

```
updates to statefulset spec for fields other than 'replicas', 'ordinals',
'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy' and
'minReadySeconds' are forbidden
```

This chart's defaults are deliberately the same 5Gi the 1.4.x chart used, so
doing nothing is correct. If you overrode either, keep the override.

```bash
kubectl get pvc -n <namespace> -o custom-columns=NAME:.metadata.name,SIZE:.spec.resources.requests.storage
```

### 2. Rewrite your values

Rename `backend:` to `server:`, delete `frontend:` entirely, and collapse the
ingress to one path. [examples/values-prod.yaml](../examples/values-prod.yaml)
is a complete 2.x example.

If you used the 1.4.x external-database keys:

```yaml
# before
database:
  enabled: false
  auth:
    customHost: pg.example.com
    customPort: "5432"
    ssl: true

# after
database:
  enabled: false
  external:
    host: pg.example.com
    port: 5432
    sslMode: require
```

### 3. Add a session secret (optional but recommended)

2.x reads `SESSION_SECRET` as a fallback encryption key. Generate one and set
`server.sessionSecret`, or add a `session-secret` key to your existing Secret.
Leave `server.aiEncryptionKey` **exactly as it was** — changing it makes every
already-encrypted value (AI credentials, bootstrap tokens, notification
secrets) unreadable.

### 4. Delete the resources Kubernetes cannot convert in place

The workload kinds and names changed, and neither a kind nor a StatefulSet's
selector can be edited in place:

```bash
# The 1.4.x Deployments
kubectl delete deployment <fullname>-backend <fullname>-frontend -n <namespace>

# The agent-files PVC — 2.x serves agent binaries from the image
kubectl delete pvc <fullname>-agent-files -n <namespace>
```

If your old release already ran the archived chart's 2.x line
(`server-statefulset`), skip this step: the names and selectors match and
`helm upgrade` handles it.

### 5. Back up the database, then upgrade

The server applies its schema migrations at boot, and they are not reversible.

```bash
kubectl exec -n <namespace> <fullname>-database-0 -- \
  pg_dump -U patchmon_user patchmon_db > patchmon-pre-2x.sql

helm upgrade patchmon . -n <namespace> -f my-values.yaml --wait --timeout 15m
```

Watch the migrations:

```bash
kubectl logs -n <namespace> -l app.kubernetes.io/component=server -f
```

### 6. Set the Server URL in the UI

This is the step that is easy to miss. In 2.x the URL PatchMon puts into agent
install commands lives in the **database**, set under Settings, and it defaults
to `http://localhost:3000`. `server.env.serverHost` and friends configure this
chart's derived CORS origin and OIDC URIs — they do not set that value.

Open Settings after logging in and set the Server URL to the address your hosts
reach PatchMon on, otherwise newly issued install commands will not resolve.

### 7. Update your agents

Existing 1.4.x agents keep reporting, but 2.x ships a new Go agent. Upstream's
migration script is at
[`tools/migrate1-4-2_to_2-0-0.sh`](https://github.com/PatchMon/PatchMon/blob/main/tools/migrate1-4-2_to_2-0-0.sh)
in the application repository.

## Rolling back

`helm rollback` restores the manifests but **not** the database: the 2.x
migrations have already run and the 1.4.x code cannot read the new schema.
A rollback therefore means restoring the dump from step 5 as well.
