{{- define "kubeconfig.tpl" }}
apiVersion: v1
kind: Config
clusters:
- name: {{ .Values.conf.capi.clusterName }}
  cluster:
    server: {{ .Values.conf.capi.apiServer }}
{{- if .Values.conf.capi.serviceAccountAuth }}
    certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
{{- else }}
    certificate-authority-data: {{ .Values.conf.capi.certificateAuthorityData | quote }}
{{- end }}
contexts:
- name: {{ .Values.conf.capi.contextName }}
  context:
    cluster: {{ .Values.conf.capi.clusterName }}
    user: {{ .Values.conf.capi.userName }}
current-context: {{ .Values.conf.capi.contextName }}
users:
- name: {{ .Values.conf.capi.userName }}
  user:
{{- if .Values.conf.capi.serviceAccountAuth }}
    tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
{{- else }}
    client-certificate-data: {{ .Values.conf.capi.clientCertificateData | quote }}
    client-key-data: {{ .Values.conf.capi.clientKeyData | quote }}
{{- end }}
{{- end }}
