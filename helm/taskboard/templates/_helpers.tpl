{{- define "taskboard.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "taskboard.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "taskboard.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "taskboard.labels" -}}
helm.sh/chart: {{ include "taskboard.chart" . }}
app.kubernetes.io/name: {{ include "taskboard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: taskboard
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "taskboard.backend.selectorLabels" -}}
app: taskboard-backend
app.kubernetes.io/name: {{ include "taskboard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: backend
{{- end }}

{{- define "taskboard.frontend.selectorLabels" -}}
app: taskboard-frontend
app.kubernetes.io/name: {{ include "taskboard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: frontend
{{- end }}

{{- define "taskboard.postgres.selectorLabels" -}}
app: taskboard-postgres
app.kubernetes.io/name: {{ include "taskboard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
{{- end }}

{{- define "taskboard.postgres.secretName" -}}
{{ include "taskboard.fullname" . }}-postgres
{{- end }}

{{- define "taskboard.postgres.host" -}}
{{ include "taskboard.fullname" . }}-postgres
{{- end }}

{{- define "taskboard.databaseUrl" -}}
postgresql+psycopg://{{ .Values.postgres.username }}:{{ .Values.postgres.password }}@{{ include "taskboard.postgres.host" . }}:{{ .Values.postgres.port }}/{{ .Values.postgres.database }}
{{- end }}

{{- define "taskboard.backend.replicas" -}}
{{- default .Values.replicaCount .Values.backend.replicas -}}
{{- end }}

{{- define "taskboard.frontend.replicas" -}}
{{- default .Values.replicaCount .Values.frontend.replicas -}}
{{- end }}
