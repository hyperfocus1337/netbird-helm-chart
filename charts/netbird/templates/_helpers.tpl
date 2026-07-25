{{/*
Expand the name of the chart.
*/}}
{{- define "netbird.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "netbird.fullname" -}}
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
Chart name and version, as used by the chart label.
*/}}
{{- define "netbird.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Allow the release namespace to be overridden.
*/}}
{{- define "netbird.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace -}}
{{- end -}}

{{/*
The public hostname. Required, since the config, the dashboard and the ingress all derive from it.
*/}}
{{- define "netbird.domain" -}}
{{- $domain := .Values.domain | default .Values.ingress.host -}}
{{- if not $domain -}}
{{- fail "netbird: .Values.domain is required, e.g. --set domain=netbird.example.com" -}}
{{- end -}}
{{- $domain -}}
{{- end -}}

{{/*
Server labels.
*/}}
{{- define "netbird.server.labels" -}}
helm.sh/chart: {{ include "netbird.chart" . }}
{{ include "netbird.server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "netbird.server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "netbird.name" . }}-server
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: server
{{- end }}

{{/*
Dashboard labels.
*/}}
{{- define "netbird.dashboard.labels" -}}
helm.sh/chart: {{ include "netbird.chart" . }}
{{ include "netbird.dashboard.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "netbird.dashboard.selectorLabels" -}}
app.kubernetes.io/name: {{ include "netbird.name" . }}-dashboard
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: dashboard
{{- end }}

{{/*
Common labels for objects that belong to neither component (ingress, ServiceMonitor).
*/}}
{{- define "netbird.common.labels" -}}
helm.sh/chart: {{ include "netbird.chart" . }}
app.kubernetes.io/name: {{ include "netbird.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Service account names.
*/}}
{{- define "netbird.server.serviceAccountName" -}}
{{- if .Values.server.serviceAccount.create }}
{{- default (printf "%s-server" (include "netbird.fullname" .)) .Values.server.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.server.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "netbird.dashboard.serviceAccountName" -}}
{{- if .Values.dashboard.serviceAccount.create }}
{{- default (printf "%s-dashboard" (include "netbird.fullname" .)) .Values.dashboard.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.dashboard.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the Secret holding config.yaml, and the key inside it.
*/}}
{{- define "netbird.server.configSecretName" -}}
{{- if .Values.server.config.existingSecret -}}
{{- .Values.server.config.existingSecret -}}
{{- else -}}
{{- printf "%s-server-config" (include "netbird.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "netbird.server.configSecretKey" -}}
{{- if .Values.server.config.existingSecret -}}
{{- default "config.yaml" .Values.server.config.existingSecretKey -}}
{{- else -}}
config.yaml
{{- end -}}
{{- end -}}

{{/*
The server's config.yaml.

Everything under server.config (minus the chart's own create/existingSecret* keys) is passed
through verbatim, so any upstream key works without the chart naming it. Only the values that
depend on the hostname are defaulted here.
*/}}
{{- define "netbird.server.config" -}}
{{- $domain := include "netbird.domain" . -}}
{{- $cfg := omit (deepCopy .Values.server.config) "create" "existingSecret" "existingSecretKey" "extra" -}}
{{- if not (get $cfg "exposedAddress") -}}
{{- $_ := set $cfg "exposedAddress" (printf "https://%s:443" $domain) -}}
{{- end -}}
{{- $auth := default dict (get $cfg "auth") -}}
{{- if not (get $auth "issuer") -}}
{{- $_ := set $auth "issuer" (printf "https://%s/oauth2" $domain) -}}
{{- end -}}
{{- if not (get $auth "dashboardRedirectURIs") -}}
{{- $_ := set $auth "dashboardRedirectURIs" (list (printf "https://%s/nb-auth" $domain) (printf "https://%s/nb-silent-auth" $domain)) -}}
{{- end -}}
{{- $owner := default dict (get $auth "owner") -}}
{{- if not (get $owner "email") -}}
{{- $auth = omit $auth "owner" -}}
{{- end -}}
{{- $_ := set $cfg "auth" $auth -}}
{{- with .Values.server.config.extra -}}
{{- $cfg = mergeOverwrite $cfg (deepCopy .) -}}
{{- end -}}
server:
{{- toYaml $cfg | nindent 2 }}
{{- end -}}

{{/*
Dashboard environment: the embedded-IdP defaults, with dashboard.env merged over them.
The defaults are the ones upstream's getting-started.sh writes into dashboard.env.
*/}}
{{- define "netbird.dashboard.env" -}}
{{- $domain := include "netbird.domain" . -}}
{{- $env := dict
  "NETBIRD_MGMT_API_ENDPOINT" (printf "https://%s" $domain)
  "NETBIRD_MGMT_GRPC_API_ENDPOINT" (printf "https://%s" $domain)
  "AUTH_AUTHORITY" (printf "https://%s/oauth2" $domain)
  "AUTH_CLIENT_ID" "netbird-dashboard"
  "AUTH_AUDIENCE" "netbird-dashboard"
  "AUTH_CLIENT_SECRET" ""
  "AUTH_SUPPORTED_SCOPES" "openid profile email groups"
  "AUTH_REDIRECT_URI" "/nb-auth"
  "AUTH_SILENT_REDIRECT_URI" "/nb-silent-auth"
  "USE_AUTH0" "false"
  "NGINX_SSL_PORT" "443"
  "LETSENCRYPT_DOMAIN" "none"
-}}
{{- with (default dict .Values.server.config.auth).issuer -}}
{{- $_ := set $env "AUTH_AUTHORITY" . -}}
{{- end -}}
{{- $env = mergeOverwrite $env (deepCopy .Values.dashboard.env) -}}
{{- /* Quoted and sorted: ConfigMap data takes strings only, so a numeric or boolean override
       (NGINX_SSL_PORT: 8443) would otherwise be rejected by the API server. */ -}}
{{- range $k := keys $env | sortAlpha }}
{{ $k }}: {{ get $env $k | quote }}
{{- end }}
{{- end -}}
