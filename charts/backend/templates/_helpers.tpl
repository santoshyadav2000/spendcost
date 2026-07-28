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
{{- $reg := .Values.image.registry | default (.Values.global).image.registry -}}
{{- if $reg -}}
{{- printf "%s/%s:%s" $reg .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end -}}

{{- define "backend.pullPolicy" -}}
{{- .Values.image.pullPolicy | default (.Values.global).image.pullPolicy | default "IfNotPresent" -}}
{{- end -}}

{{- define "backend.secretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else -}}
{{- printf "%s-secret" (include "backend.fullname" .) -}}
{{- end -}}
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

{{/* Resolved in-cluster DB host */}}
{{- define "backend.dbHost" -}}
{{- if .Values.database.host -}}
{{- .Values.database.host -}}
{{- else -}}
{{- printf "%s-postgres.%s.svc.cluster.local" .Release.Name (include "backend.namespace" .) -}}
{{- end -}}
{{- end -}}

{{/* Resolved DATABASE_URL (explicit url wins, otherwise built from parts) */}}
{{- define "backend.databaseUrl" -}}
{{- if .Values.database.url -}}
{{- .Values.database.url -}}
{{- else -}}
{{- printf "%s://%s:%s@%s:%v/%s" .Values.database.driver .Values.database.user .Values.database.password (include "backend.dbHost" .) .Values.database.port .Values.database.name -}}
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
{{- .Values.ingress.className | default (.Values.global).ingress.className -}}
{{- end -}}
