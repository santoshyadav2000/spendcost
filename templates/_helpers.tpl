{{/*
Umbrella-level shared helpers.
*/}}

{{/* Resolved namespace name. */}}
{{- define "cloudcost.namespace" -}}
{{- .Values.global.namespace.name | default "cloudcost" -}}
{{- end -}}

{{/* Common labels applied to umbrella-owned objects. */}}
{{- define "cloudcost.commonLabels" -}}
app.kubernetes.io/part-of: cloudcost
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}
