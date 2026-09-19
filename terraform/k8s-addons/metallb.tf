resource "helm_release" "metallb" {
  depends_on       = [helm_release.calico]
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  namespace        = "metallb-system"
  create_namespace = true
}

# MetalLB's chart doesn't expose IPAddressPool via values, so these are
# applied as raw CRs via the kubectl provider (kubernetes_manifest would try
# to validate against the CRD schema at plan time, before the CRD the same
# apply just created is known — kubectl_manifest skips that problem).
resource "kubectl_manifest" "metallb_pool" {
  depends_on = [helm_release.metallb]
  yaml_body = yamlencode({
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "new-cluster-pool"
      namespace = "metallb-system"
    }
    spec = {
      addresses = var.metallb_pool
    }
  })
}

resource "kubectl_manifest" "metallb_l2" {
  depends_on = [kubectl_manifest.metallb_pool]
  yaml_body = yamlencode({
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "new-cluster-l2"
      namespace = "metallb-system"
    }
  })
}
