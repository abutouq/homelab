{{- define "homelab-bots.labels" -}}
app.kubernetes.io/part-of: homelab-bots
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}

{{- define "homelab-bots.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end }}

{{/* Shared pod settings for every bot container. Args: root context. */}}
{{- define "homelab-bots.podCommon" -}}
imagePullSecrets:
  - name: {{ .Values.externalSecrets.registry.secretName }}
{{- end }}
