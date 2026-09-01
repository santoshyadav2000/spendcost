{{/* Base name */}}
{{- define "database.name" -}}
{{- default "postgres" .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fullname */}}
{{- define "database.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "database.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Headless service name for stable DNS */}}
{{- define "database.headlessService" -}}
{{- printf "%s-headless" (include "database.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Namespace (inherit global when not overridden) */}}
{{- define "database.namespace" -}}
{{- if .Values.namespaceOverride -}}
{{- .Values.namespaceOverride -}}
{{- else -}}
{{- (.Values.global).namespace.name | default "cloudcost" -}}
{{- end -}}
{{- end -}}

{{/* Image reference — all database settings come from global.database */}}
{{- define "database.image" -}}
{{- $img := .Values.global.database.image -}}
{{- if $img.registry -}}
{{- printf "%s/%s:%s" $img.registry $img.repository $img.tag -}}
{{- else -}}
{{- printf "%s:%s" $img.repository $img.tag -}}
{{- end -}}
{{- end -}}

{{- define "database.pullPolicy" -}}
{{- .Values.global.database.image.pullPolicy | default "IfNotPresent" -}}
{{- end -}}

{{/* Secret name holding credentials */}}
{{- define "database.secretName" -}}
{{- printf "%s-auth" (include "database.fullname" .) -}}
{{- end -}}

{{/* Selector labels */}}
{{- define "database.selectorLabels" -}}
app.kubernetes.io/name: {{ include "database.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
{{- end -}}

{{/* Common labels */}}
{{- define "database.labels" -}}
{{ include "database.selectorLabels" . }}
app.kubernetes.io/part-of: cloudcost
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- with (.Values.global).labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}
