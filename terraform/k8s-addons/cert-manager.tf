# Base cert-manager install only (controller + CRDs). Wiring a ClusterIssuer
# (e.g. Let's Encrypt via Cloudflare DNS-01, matching the existing cluster's
# pattern in ansible/install_cert_manager.yml) is a deliberate follow-up once
# this base install is confirmed working, not assumed here.
resource "helm_release" "cert_manager" {
  depends_on       = [helm_release.calico]
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]
}
