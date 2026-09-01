{{- define "frontend.name" -}}
{{- default "frontend" .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "frontend.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "frontend.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "frontend.namespace" -}}
{{- if .Values.namespaceOverride -}}
{{- .Values.namespaceOverride -}}
{{- else -}}
{{- (.Values.global).namespace.name | default "cloudcost" -}}
{{- end -}}
{{- end -}}

{{- define "frontend.image" -}}
{{- $reg := .Values.image.registry -}}
{{- if $reg -}}
{{- printf "%s/%s:%s" $reg .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end -}}

{{- define "frontend.pullPolicy" -}}
{{- .Values.image.pullPolicy | default "IfNotPresent" -}}
{{- end -}}

{{- define "frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: frontend
{{- end -}}

{{- define "frontend.labels" -}}
{{ include "frontend.selectorLabels" . }}
app.kubernetes.io/part-of: cloudcost
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- with (.Values.global).labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "frontend.ingressClassName" -}}
{{- .Values.ingress.className -}}
{{- end -}}
