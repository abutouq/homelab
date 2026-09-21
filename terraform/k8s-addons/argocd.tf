resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.3.0" # Check artifacthub.io/packages/helm/argo/argo-cd for the latest version
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false

  # Exposed via a pinned MetalLB LoadBalancer IP rather than Ingress —
  # Teleport's app_service (on 192.168.0.158, see ansible/teleport_apps.yml)
  # proxies to this address directly. --insecure means argocd-server serves
  # plain HTTP; Teleport terminates TLS for end users at its own proxy.
  set = [
    {
      name  = "server.service.type"
      value = "LoadBalancer"
    },
    {
      name  = "server.service.annotations.metallb\\.io/loadBalancerIPs"
      value = "192.168.0.30"
    },
    {
      name  = "server.extraArgs[0]"
      value = "--insecure"
    }
  ]

  # Optional: Supply a dedicated values file for fine-grained tuning
  values = [
    file("${path.module}/values.yaml")
  ]

  depends_on = [kubernetes_namespace.argocd, helm_release.calico]
}