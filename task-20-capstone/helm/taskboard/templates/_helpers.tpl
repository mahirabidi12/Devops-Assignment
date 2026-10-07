{{- define "taskboard.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "taskboard.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "taskboard.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "taskboard.labels" -}}
app.kubernetes.io/name: {{ include "taskboard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/* Selector labels exclude version: a Deployment's selector is immutable, so
     including it would make an appVersion bump unappliable. */}}
{{- define "taskboard.selectorLabels" -}}
app.kubernetes.io/name: {{ include "taskboard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "taskboard.databaseUrl" -}}
postgresql+psycopg2://{{ .Values.postgres.user }}:{{ .Values.postgres.password }}@{{ include "taskboard.fullname" . }}-postgres:5432/{{ .Values.postgres.database }}
{{- end -}}

{{/* Image reference for a component. The registry is optional: with it empty
     the name must not start with a slash, or the kubelet rejects it with
     InvalidImageName. Takes a dict of (root, component, tag). */}}
{{- define "taskboard.image" -}}
{{- $registry := .root.Values.image.registry -}}
{{- $name := printf "%s-%s" .root.Values.image.repository .component -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $name .tag -}}
{{- else -}}
{{- printf "%s:%s" $name .tag -}}
{{- end -}}
{{- end -}}
