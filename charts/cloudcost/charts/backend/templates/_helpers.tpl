{{- define "backend.name" -}}
{{- default "backend" .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "backend.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "backend.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "backend.namespace" -}}
{{- if .Values.namespaceOverride -}}
{{- .Values.namespaceOverride -}}
{{- else -}}
{{- (.Values.global).namespace.name | default "cloudcost" -}}
{{- end -}}
{{- end -}}

{{- define "backend.image" -}}
{{- $reg := .Values.image.registry -}}
{{- if $reg -}}
{{- printf "%s/%s:%s" $reg .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end -}}

{{- define "backend.pullPolicy" -}}
{{- .Values.image.pullPolicy | default "IfNotPresent" -}}
{{- end -}}

{{- define "backend.secretName" -}}
{{- printf "%s-secret" (include "backend.fullname" .) -}}
{{- end -}}

{{- define "backend.configName" -}}
{{- printf "%s-config" (include "backend.fullname" .) -}}
{{- end -}}

{{- define "backend.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "backend.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/* In-cluster PostgreSQL service host (deploy mode) */}}
{{- define "backend.dbHost" -}}
{{- printf "%s-postgres.%s.svc.cluster.local" .Release.Name (include "backend.namespace" .) -}}
{{- end -}}

{{/* DATABASE_URL for EXTERNAL mode only — the full connection string from values.
     `default ""` normalizes a fully-commented-out/missing `url:` key to an
     empty string here, before it ever gets printed — without this, printing
     a genuinely missing value produces the literal text "<no value>", which
     is a non-empty string that silently passes the "must be set" check
     further down (secret.yaml), instead of being caught by it. */}}
{{- define "backend.databaseUrl" -}}
{{- .Values.global.database.url | default "" -}}
{{- end -}}

{{/* Name of the Secret the database subchart creates (deploy mode) */}}
{{- define "backend.dbSecretName" -}}
{{- printf "%s-postgres-auth" .Release.Name -}}
{{- end -}}

{{/* Deploy-mode DB env: read credentials from the database Secret and build
     DATABASE_URL from them at runtime (so nothing is in values.yaml). */}}
{{- define "backend.dbEnv" -}}
{{- $db := .Values.global.database -}}
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "backend.dbSecretName" . }}
      key: POSTGRES_USER
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "backend.dbSecretName" . }}
      key: POSTGRES_PASSWORD
- name: POSTGRES_DB
  valueFrom:
    secretKeyRef:
      name: {{ include "backend.dbSecretName" . }}
      key: POSTGRES_DB
- name: DATABASE_URL
  value: "postgresql+asyncpg://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@{{ include "backend.dbHost" . }}:{{ $db.service.port }}/$(POSTGRES_DB)"
{{- end -}}

{{/* Google OAuth redirect URI — DYNAMIC.
     If an ingress host is set, build "<scheme>://<host>/api/auth/google/callback"
     (https when TLS is configured). If no host (IP mode), fall back to the
     explicit config.redirectUri, since OAuth needs an absolute URL. */}}
{{- define "backend.redirectUri" -}}
{{- $host := "" -}}
{{- range .Values.ingress.hosts -}}
{{- if and (not $host) .host -}}{{- $host = .host -}}{{- end -}}
{{- end -}}
{{- if and .Values.ingress.enabled $host -}}
{{- $scheme := "http" -}}
{{- if .Values.ingress.tls -}}{{- $scheme = "https" -}}{{- end -}}
{{- printf "%s://%s/api/auth/google/callback" $scheme $host -}}
{{- else -}}
{{- .Values.config.redirectUri -}}
{{- end -}}
{{- end -}}

{{- define "backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: backend
{{- end -}}

{{- define "backend.labels" -}}
{{ include "backend.selectorLabels" . }}
app.kubernetes.io/part-of: cloudcost
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- with (.Values.global).labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "backend.ingressClassName" -}}
{{- .Values.ingress.className -}}
{{- end -}}
