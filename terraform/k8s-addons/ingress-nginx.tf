# Depends on MetalLB's pool/advertisement existing first, since the
# controller Service below requests a LoadBalancer IP from that pool.
resource "helm_release" "ingress_nginx" {
  depends_on       = [kubectl_manifest.metallb_l2]
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  set = [
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    }
  ]
}
