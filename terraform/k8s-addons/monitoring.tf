# Exporters for the external Prometheus on tf-grafana-01 (192.168.0.23), plus a
# read-only identity for it. That VM can't reach pod IPs, so it scrapes
# everything through the API server's proxy (pods/proxy, nodes/proxy,
# services/proxy) with the token below, which is handed over via Vault
# (secret/homelab/prometheus-k8s) and rendered into the VM's cloud-init.

resource "kubernetes_namespace" "monitoring" {
  depends_on = [helm_release.calico]
  metadata {
    name = "monitoring"
    # node-exporter uses hostNetwork and host /proc, /sys.
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "helm_release" "node_exporter" {
  depends_on = [kubernetes_namespace.monitoring]
  name       = "node-exporter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-node-exporter"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [yamlencode({
    # Every node, control planes included.
    tolerations = [{ operator = "Exists" }]
    resources = {
      requests = { cpu = "10m", memory = "24Mi" }
      limits   = { memory = "64Mi" }
    }
  })]
}

resource "helm_release" "kube_state_metrics" {
  depends_on = [kubernetes_namespace.monitoring]
  name       = "kube-state-metrics"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-state-metrics"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [yamlencode({
    resources = {
      requests = { cpu = "10m", memory = "32Mi" }
      limits   = { memory = "128Mi" }
    }
  })]
}

# --- Read-only identity for the external Prometheus ---------------------------
resource "kubernetes_service_account" "prometheus_external" {
  metadata {
    name      = "prometheus-external"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "prometheus_external" {
  metadata {
    name = "prometheus-external"
  }
  rule {
    api_groups = [""]
    resources  = ["nodes", "nodes/metrics", "services", "endpoints", "pods"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["nodes/proxy", "pods/proxy", "services/proxy"]
    verbs      = ["get"]
  }
  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }
}

resource "kubernetes_cluster_role_binding" "prometheus_external" {
  metadata {
    name = "prometheus-external"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.prometheus_external.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.prometheus_external.metadata[0].name
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
}

resource "kubernetes_secret" "prometheus_external" {
  metadata {
    name      = "prometheus-external-token"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.prometheus_external.metadata[0].name
    }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

# Handed to the root stack, which renders it into tf-grafana-01's cloud-init.
# On a from-scratch build this path doesn't exist yet when the root stack first
# runs; it then simply skips the cluster scrape jobs, and the next root apply
# (after this one) recreates tf-grafana-01 with them.
resource "vault_kv_secret_v2" "prometheus_k8s" {
  mount = "secret"
  name  = "homelab/prometheus-k8s"
  data_json = jsonencode({
    api_server = trimprefix(var.kubernetes_api_url, "https://")
    token      = kubernetes_secret.prometheus_external.data["token"]
    ca_crt     = kubernetes_secret.prometheus_external.data["ca.crt"]
  })
}
