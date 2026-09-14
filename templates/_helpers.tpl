{{/*
Expand the name of the chart.
*/}}
{{- define "patchmon.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "patchmon.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart name and version as used by the chart label.
*/}}
{{- define "patchmon.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "patchmon.labels" -}}
helm.sh/chart: {{ include "patchmon.chart" . }}
{{ include "patchmon.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/part-of: patchmon
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "patchmon.selectorLabels" -}}
app.kubernetes.io/name: {{ include "patchmon.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Per-component labels and selector labels.

The bare `app:` selector label is kept for backwards compatibility with the
1.x chart and with the kubectl snippets in the README; removing it would be a
breaking change to StatefulSet selectors, which are immutable.
*/}}
{{- define "patchmon.database.labels" -}}
{{ include "patchmon.labels" . }}
app.kubernetes.io/component: database
{{- end }}

{{- define "patchmon.database.selectorLabels" -}}
{{ include "patchmon.selectorLabels" . }}
app.kubernetes.io/component: database
app: {{ include "patchmon.fullname" . }}-database
{{- end }}

{{- define "patchmon.redis.labels" -}}
{{ include "patchmon.labels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{- define "patchmon.redis.selectorLabels" -}}
{{ include "patchmon.selectorLabels" . }}
app.kubernetes.io/component: redis
app: {{ include "patchmon.fullname" . }}-redis
{{- end }}

{{- define "patchmon.server.labels" -}}
{{ include "patchmon.labels" . }}
app.kubernetes.io/component: server
{{- end }}

{{- define "patchmon.server.selectorLabels" -}}
{{ include "patchmon.selectorLabels" . }}
app.kubernetes.io/component: server
app: {{ include "patchmon.fullname" . }}-server
{{- end }}

{{- define "patchmon.guacd.labels" -}}
{{ include "patchmon.labels" . }}
app.kubernetes.io/component: guacd
{{- end }}

{{- define "patchmon.guacd.selectorLabels" -}}
{{ include "patchmon.selectorLabels" . }}
app.kubernetes.io/component: guacd
app: {{ include "patchmon.fullname" . }}-guacd
{{- end }}

{{/*
Name of the service account to use.
*/}}
{{- define "patchmon.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "patchmon.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resource names.
*/}}
{{- define "patchmon.database.name" -}}
{{- printf "%s-database" (include "patchmon.fullname" .) -}}
{{- end -}}

{{- define "patchmon.redis.name" -}}
{{- printf "%s-redis" (include "patchmon.fullname" .) -}}
{{- end -}}

{{- define "patchmon.server.name" -}}
{{- printf "%s-server" (include "patchmon.fullname" .) -}}
{{- end -}}

{{- define "patchmon.guacd.name" -}}
{{- printf "%s-guacd" (include "patchmon.fullname" .) -}}
{{- end -}}

{{/*
Cluster-internal FQDNs. Fully qualified so resolution does not depend on the
pod's search-domain list, which matters for the wait-for-* init containers.
*/}}
{{- define "patchmon.database.fqdn" -}}
{{- printf "%s.%s.svc.cluster.local" (include "patchmon.database.name" .) .Release.Namespace -}}
{{- end -}}

{{- define "patchmon.redis.fqdn" -}}
{{- printf "%s.%s.svc.cluster.local" (include "patchmon.redis.name" .) .Release.Namespace -}}
{{- end -}}

{{- define "patchmon.guacd.fqdn" -}}
{{- printf "%s.%s.svc.cluster.local" (include "patchmon.guacd.name" .) .Release.Namespace -}}
{{- end -}}

{{/*
Effective connection endpoints. When the bundled component is disabled the
matching `external.*` values take over.
*/}}
{{- define "patchmon.database.host" -}}
{{- if .Values.database.enabled -}}
{{- include "patchmon.database.fqdn" . -}}
{{- else -}}
{{- required "database.enabled is false, so database.external.host must be set" .Values.database.external.host -}}
{{- end -}}
{{- end -}}

{{- define "patchmon.database.port" -}}
{{- if .Values.database.enabled -}}
{{- .Values.database.service.port -}}
{{- else -}}
{{- .Values.database.external.port | default 5432 -}}
{{- end -}}
{{- end -}}

{{- define "patchmon.redis.host" -}}
{{- if .Values.redis.enabled -}}
{{- include "patchmon.redis.fqdn" . -}}
{{- else -}}
{{- required "redis.enabled is false, so redis.external.host must be set" .Values.redis.external.host -}}
{{- end -}}
{{- end -}}

{{- define "patchmon.redis.port" -}}
{{- if .Values.redis.enabled -}}
{{- .Values.redis.service.port -}}
{{- else -}}
{{- .Values.redis.external.port | default 6379 -}}
{{- end -}}
{{- end -}}

{{- define "patchmon.guacd.address" -}}
{{- if .Values.guacd.enabled -}}
{{- printf "%s:%v" (include "patchmon.guacd.fqdn" .) .Values.guacd.service.port -}}
{{- else -}}
{{- .Values.guacd.externalAddress | default "" -}}
{{- end -}}
{{- end -}}

{{/*
DATABASE_URL. The password is interpolated as $(POSTGRES_PASSWORD), which
kubelet expands from the env var of that name on the same container, so the
password never appears in the rendered manifest.

sslmode is appended only for an external database: connections to the bundled
StatefulSet stay inside the cluster and that server has TLS disabled, so
requiring it there would just refuse to connect.
*/}}
{{- define "patchmon.databaseUrl" -}}
{{- $host := include "patchmon.database.host" . -}}
{{- $port := include "patchmon.database.port" . -}}
{{- $user := .Values.database.auth.username -}}
{{- $db := .Values.database.auth.database -}}
{{- $url := printf "postgresql://%s:$(POSTGRES_PASSWORD)@%s:%s/%s" $user $host $port $db -}}
{{- if not .Values.database.enabled -}}
{{- $params := list (printf "sslmode=%s" (.Values.database.external.sslMode | default "require")) -}}
{{- with .Values.database.external.extraParams -}}
{{- $params = concat $params (list .) -}}
{{- end -}}
{{- $url = printf "%s?%s" $url (join "&" $params) -}}
{{- end -}}
{{- $url -}}
{{- end -}}

{{/*
Secret names. Each credential resolves independently so a deployment can mix
chart-managed and externally managed secrets.
*/}}
{{- define "patchmon.secretName" -}}
{{- printf "%s-secrets" (include "patchmon.fullname" .) -}}
{{- end -}}

{{- define "patchmon.database.secretName" -}}
{{- .Values.database.auth.existingSecret | default (include "patchmon.secretName" .) -}}
{{- end -}}

{{- define "patchmon.redis.secretName" -}}
{{- .Values.redis.auth.existingSecret | default (include "patchmon.secretName" .) -}}
{{- end -}}

{{- define "patchmon.server.secretName" -}}
{{- .Values.server.existingSecret | default (include "patchmon.secretName" .) -}}
{{- end -}}

{{/*
OIDC client secret can live in its own secret, independent of server.existingSecret.
*/}}
{{- define "patchmon.oidc.secretName" -}}
{{- .Values.server.oidc.existingSecret | default (include "patchmon.server.secretName" .) -}}
{{- end -}}

{{- define "patchmon.configMapName" -}}
{{- printf "%s-config" (include "patchmon.fullname" .) -}}
{{- end -}}

{{/*
Image references. global.imageRegistry, when set, replaces the per-component
registry so an air-gapped mirror can be pointed at in one place.
*/}}
{{- define "patchmon.image" -}}
{{- $registry := .global.imageRegistry | default .image.registry -}}
{{- $tag := .tag | default .image.tag -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry .image.repository $tag -}}
{{- else -}}
{{- printf "%s:%s" .image.repository $tag -}}
{{- end -}}
{{- end -}}

{{- define "patchmon.database.image" -}}
{{- include "patchmon.image" (dict "image" .Values.database.image "global" .Values.global) -}}
{{- end -}}

{{- define "patchmon.redis.image" -}}
{{- include "patchmon.image" (dict "image" .Values.redis.image "global" .Values.global) -}}
{{- end -}}

{{- define "patchmon.guacd.image" -}}
{{- include "patchmon.image" (dict "image" .Values.guacd.image "global" .Values.global) -}}
{{- end -}}

{{/*
Server image. global.imageTag overrides server.image.tag so a single value can
pin the PatchMon version across an umbrella chart.
*/}}
{{- define "patchmon.server.image" -}}
{{- include "patchmon.image" (dict "image" .Values.server.image "global" .Values.global "tag" .Values.global.imageTag) -}}
{{- end -}}

{{/*
Image used by the wait-for-* and fix-permissions init containers.
*/}}
{{- define "patchmon.initContainer.image" -}}
{{- include "patchmon.image" (dict "image" .Values.initContainerImage "global" .Values.global) -}}
{{- end -}}

{{/*
Storage class: global.storageClass wins over the per-component value, so a
cluster-wide class can be set once.
*/}}
{{- define "patchmon.storageClass" -}}
{{- $storageClass := .global.storageClass | default .local -}}
{{- if $storageClass -}}
{{- printf "%s" $storageClass -}}
{{- end -}}
{{- end -}}

{{/*
Base URL PatchMon is reached on, derived from server.env.serverProtocol /
serverHost / serverPort. Used for CORS_ORIGIN, FRONTEND_URL and the OIDC
redirect and post-logout URIs. The port is omitted when it is the default for
the scheme, because an origin with a redundant :443 will not match.
*/}}
{{- define "patchmon.externalUrl" -}}
{{- $protocol := .Values.server.env.serverProtocol | default "http" -}}
{{- $host := required "server.env.serverHost must be set" .Values.server.env.serverHost -}}
{{- $port := .Values.server.env.serverPort | default "" | toString -}}
{{- if or (eq $port "") (and (eq $protocol "http") (eq $port "80")) (and (eq $protocol "https") (eq $port "443")) -}}
{{- printf "%s://%s" $protocol $host -}}
{{- else -}}
{{- printf "%s://%s:%s" $protocol $host $port -}}
{{- end -}}
{{- end -}}

{{/*
CORS_ORIGIN. Must match the origin the browser sends. Override
server.env.corsOrigin to allow several origins (comma-separated, no spaces).
*/}}
{{- define "patchmon.corsOrigin" -}}
{{- .Values.server.env.corsOrigin | default (include "patchmon.externalUrl" .) -}}
{{- end -}}

{{- define "patchmon.oidc.redirectUri" -}}
{{- .Values.server.oidc.redirectUri | default (printf "%s/api/v1/auth/oidc/callback" (include "patchmon.externalUrl" .)) -}}
{{- end -}}

{{- define "patchmon.oidc.postLogoutUri" -}}
{{- .Values.server.oidc.postLogoutUri | default (printf "%s/login" (include "patchmon.externalUrl" .)) -}}
{{- end -}}

{{/*
Mapping from PatchMon environment variable to the key under `server.env` that
carries it. Rendered as YAML and parsed back so the list stays declarative.

Only the settings whose value is neither null nor "" are emitted, because
PatchMon resolves each setting as environment > database > default: emitting a
variable pins it and greys the field out in the Settings UI. `false` and `0`
are meaningful values and are emitted.

Variables that need more than a lookup — DATABASE_URL, the Redis endpoint, the
secrets, PORT, CORS_ORIGIN, GUACD_ADDRESS, POD_ID and the OIDC block — are
built explicitly in the StatefulSet instead.

SERVER_PROTOCOL / SERVER_HOST / SERVER_PORT are carried for continuity with the
1.x chart and because they show up on the Settings diagnostics page, but in 2.x
they change no behaviour: the server URL is a database setting. They are what
this chart derives the CORS origin and the OIDC URIs from.
*/}}
{{- define "patchmon.server.envMap" -}}
ENABLE_LOGGING: enableLogging
LOG_LEVEL: logLevel
TZ: timezone
TRUST_PROXY: trustProxy
TRUSTED_PROXY_RANGES: trustedProxyRanges
ENABLE_HSTS: enableHsts
SERVER_PROTOCOL: serverProtocol
SERVER_HOST: serverHost
SERVER_PORT: serverPort
DB_CONNECTION_LIMIT: dbConnectionLimit
DB_POOL_TIMEOUT: dbPoolTimeout
DB_CONNECT_TIMEOUT: dbConnectTimeout
DB_IDLE_TIMEOUT: dbIdleTimeout
DB_MAX_LIFETIME: dbMaxLifetime
DB_TRANSACTION_LONG_TIMEOUT: dbTransactionLongTimeout
PM_DB_CONN_MAX_ATTEMPTS: dbConnMaxAttempts
PM_DB_CONN_WAIT_INTERVAL: dbConnWaitInterval
REDIS_DB: redisDb
RATE_LIMIT_WINDOW_MS: rateLimitWindowMs
RATE_LIMIT_MAX: rateLimitMax
AUTH_RATE_LIMIT_WINDOW_MS: authRateLimitWindowMs
AUTH_RATE_LIMIT_MAX: authRateLimitMax
AGENT_RATE_LIMIT_WINDOW_MS: agentRateLimitWindowMs
AGENT_RATE_LIMIT_MAX: agentRateLimitMax
PASSWORD_RATE_LIMIT_WINDOW_MS: passwordRateLimitWindowMs
PASSWORD_RATE_LIMIT_MAX: passwordRateLimitMax
JSON_BODY_LIMIT: jsonBodyLimit
AGENT_UPDATE_BODY_LIMIT: agentUpdateBodyLimit
COMPLIANCE_BODY_LIMIT: complianceBodyLimit
AGENT_PING_BODY_LIMIT: agentPingBodyLimit
JWT_EXPIRES_IN: jwtExpiresIn
AUTH_BROWSER_SESSION_COOKIES: authBrowserSessionCookies
MAX_LOGIN_ATTEMPTS: maxLoginAttempts
LOCKOUT_DURATION_MINUTES: lockoutDurationMinutes
SESSION_INACTIVITY_TIMEOUT_MINUTES: sessionInactivityTimeoutMinutes
MAX_TFA_ATTEMPTS: maxTfaAttempts
TFA_LOCKOUT_DURATION_MINUTES: tfaLockoutDurationMinutes
TFA_REMEMBER_ME_EXPIRES_IN: tfaRememberMeExpiresIn
TFA_MAX_REMEMBER_SESSIONS: tfaMaxRememberSessions
PASSWORD_MIN_LENGTH: passwordMinLength
PASSWORD_REQUIRE_UPPERCASE: passwordRequireUppercase
PASSWORD_REQUIRE_LOWERCASE: passwordRequireLowercase
PASSWORD_REQUIRE_NUMBER: passwordRequireNumber
PASSWORD_REQUIRE_SPECIAL: passwordRequireSpecial
DEFAULT_USER_ROLE: defaultUserRole
PATCH_RUN_STALL_TIMEOUT_MIN: patchRunStallTimeoutMin
AGENT_REPORTS_RETENTION_DAYS: agentReportsRetentionDays
{{- end -}}

{{/*
The OIDC group-name variables, keyed by the `server.oidc.groups` entry.
*/}}
{{- define "patchmon.oidc.groupEnvMap" -}}
OIDC_SUPERADMIN_GROUP: superadmin
OIDC_ADMIN_GROUP: admin
OIDC_HOST_MANAGER_GROUP: hostManager
OIDC_USER_GROUP: user
OIDC_READONLY_GROUP: readonly
{{- end -}}

{{/*
Fail early on a configuration that cannot possibly start, so the message names
the value rather than surfacing as a CrashLoopBackOff.
*/}}
{{- define "patchmon.validateValues" -}}
{{- if and .Values.server.enabled (not .Values.server.existingSecret) (not .Values.server.jwtSecret) -}}
{{- fail "server.jwtSecret is required (or set server.existingSecret). Generate one with: openssl rand -hex 64" -}}
{{- end -}}
{{- if and .Values.server.enabled (not .Values.server.existingSecret) (not .Values.server.aiEncryptionKey) -}}
{{- fail "server.aiEncryptionKey is required (or set server.existingSecret). Generate one with: openssl rand -hex 64" -}}
{{- end -}}
{{- if and (not .Values.database.auth.existingSecret) (not .Values.database.auth.password) -}}
{{- fail "database.auth.password is required (or set database.auth.existingSecret)" -}}
{{- end -}}
{{- if and (not .Values.redis.auth.existingSecret) (not .Values.redis.auth.password) -}}
{{- fail "redis.auth.password is required (or set redis.auth.existingSecret)" -}}
{{- end -}}
{{- if and .Values.server.oidc.enabled (not .Values.server.oidc.existingSecret) (not .Values.server.existingSecret) (not .Values.server.oidc.clientSecret) -}}
{{- fail "server.oidc.enabled is true, so server.oidc.clientSecret is required (or set server.oidc.existingSecret)" -}}
{{- end -}}
{{- if and .Values.server.oidc.enabled (not .Values.server.oidc.issuerUrl) -}}
{{- fail "server.oidc.enabled is true, so server.oidc.issuerUrl is required" -}}
{{- end -}}
{{- if and .Values.server.oidc.enabled (not .Values.server.oidc.clientId) -}}
{{- fail "server.oidc.enabled is true, so server.oidc.clientId is required" -}}
{{- end -}}
{{- if and (not .Values.database.enabled) (not .Values.database.external.host) -}}
{{- fail "database.enabled is false, so database.external.host is required" -}}
{{- end -}}
{{- if and (not .Values.redis.enabled) (not .Values.redis.external.host) -}}
{{- fail "redis.enabled is false, so redis.external.host is required" -}}
{{- end -}}
{{- if and .Values.server.autoscaling.enabled (gt (int .Values.server.autoscaling.minReplicas) (int .Values.server.autoscaling.maxReplicas)) -}}
{{- fail "server.autoscaling.minReplicas must not exceed server.autoscaling.maxReplicas" -}}
{{- end -}}
{{- /*
With secret.create false nothing renders the chart's own Secret, so every
credential has to name an existing one — otherwise the pod references a Secret
that was never created and sits in CreateContainerConfigError.
*/ -}}
{{- if not .Values.secret.create -}}
{{- if not .Values.database.auth.existingSecret -}}
{{- fail "secret.create is false, so database.auth.existingSecret must be set" -}}
{{- end -}}
{{- if not .Values.redis.auth.existingSecret -}}
{{- fail "secret.create is false, so redis.auth.existingSecret must be set" -}}
{{- end -}}
{{- if and .Values.server.enabled (not .Values.server.existingSecret) -}}
{{- fail "secret.create is false, so server.existingSecret must be set" -}}
{{- end -}}
{{- if and .Values.server.oidc.enabled (not .Values.server.oidc.existingSecret) (not .Values.server.existingSecret) -}}
{{- fail "secret.create is false and OIDC is enabled, so server.oidc.existingSecret must be set" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Probe action for the server container. `type` is "tcpSocket" or "httpGet";
anything else is a values error rather than a silently empty probe.
*/}}
{{- define "patchmon.server.probeAction" -}}
{{- if eq .type "tcpSocket" -}}
tcpSocket:
  port: http
{{- else if eq .type "httpGet" -}}
httpGet:
  path: /health
  port: http
  # The kubelet sends the pod IP as the Host header, and PatchMon's CORS
  # middleware answers 403 host_mismatch for any Host that is neither
  # loopback nor derived from CORS_ORIGIN. Upstream's own health check runs
  # inside the container against localhost, so this only bites on Kubernetes.
  httpHeaders:
    - name: Host
      value: localhost
{{- else -}}
{{- fail (printf "probe type must be tcpSocket or httpGet, got %q" .type) -}}
{{- end -}}
{{- end -}}
