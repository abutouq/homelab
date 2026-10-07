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

# Teleport app access, served by this agent rather than the control plane so that
# adding an app is a pod rollout, not a control-plane rebuild. Targets must be
# reachable from pods: in-cluster services, or LAN ports that aren't bound to
# localhost (Prometheus, Alertmanager, Uptime Kuma and Pi-hole on .158 are, so
# they stay on the old Teleport there). Each app is served at <name>.teleport.homebytes.space.
locals {
  teleport_apps = [
    { name = "argocd", uri = "http://argocd-server.argocd.svc.cluster.local:80" }, # argocd-server runs --insecure
    { name = "grafana", uri = "http://192.168.0.23:3000" },                        # tf-grafana-01
    { name = "immich", uri = "http://192.168.0.158:2283" },
    { name = "localstack", uri = "http://192.168.0.158:4566" },
  ]
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
    roles           = "kube,app"
    apps            = local.teleport_apps
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
