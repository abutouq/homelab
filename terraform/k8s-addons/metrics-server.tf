# --kubelet-insecure-tls is needed because this homelab's kubelet serving
# certs are the kubeadm-generated self-signed ones, not signed by a CA
# metrics-server trusts by default.
resource "helm_release" "metrics_server" {
  depends_on = [helm_release.calico]
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"

  set = [
    {
      name  = "args[0]"
      value = "--kubelet-insecure-tls"
    }
  ]
}
