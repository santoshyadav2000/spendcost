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

{{/* Image reference honouring global registry fallback */}}
{{- define "database.image" -}}
{{- $reg := .Values.image.registry | default (.Values.global).image.registry -}}
{{- if $reg -}}
{{- printf "%s/%s:%s" $reg .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end -}}

{{- define "database.pullPolicy" -}}
{{- .Values.image.pullPolicy | default (.Values.global).image.pullPolicy | default "IfNotPresent" -}}
{{- end -}}

{{/* Secret name holding credentials */}}
{{- define "database.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else -}}
{{- printf "%s-auth" (include "database.fullname" .) -}}
{{- end -}}
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
