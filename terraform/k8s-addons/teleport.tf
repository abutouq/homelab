# Kube agent: dials out to the Teleport control plane (tf-teleport-apps-01), so no
# inbound ports are needed. The join token is created in ../main.tf and stored in Vault;
# it must also be registered on the control plane once (see ../README.md), or the
# agent will sit in CrashLoopBackOff with "token not found".
#
# Pinned to the chart that matches the control plane's major version (agents may not
# be newer than the auth server).
data "vault_kv_secret_v2" "teleport" {
  mount = "secret"
  name  = "homelab/teleport"
}

resource "helm_release" "teleport_kube_agent" {
  depends_on       = [helm_release.calico]
  name             = "teleport-kube-agent"
  repository       = "https://charts.releases.teleport.dev"
  chart            = "teleport-kube-agent"
  version          = "18.9.2"
  namespace        = "teleport"
  create_namespace = true

  values = [yamlencode({
    roles           = "kube"
    proxyAddr       = "teleport.homebytes.space:443"
    kubeClusterName = "proxmox-homelab"
    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
    }
  })]

  set_sensitive = [
    {
      name  = "authToken"
      value = data.vault_kv_secret_v2.teleport.data["kube_token"]
    }
  ]
}
