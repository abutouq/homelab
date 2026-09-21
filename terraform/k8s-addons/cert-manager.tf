# Lightweight install: cainjector disabled (only needed by other operators
# wanting cert-manager to auto-inject CA bundles into their own webhook
# configs via the cert-manager.io/inject-ca-from annotation — nothing here
# uses that), startupapicheck disabled (a one-shot Job that just probes the
# webhook post-install; skipping it saves a pod, not a capability), and
# small explicit resource requests/limits so the remaining two components
# (controller, webhook) are scheduled predictably instead of BestEffort
# with no bound at all (the chart's default).
#
# Wiring a ClusterIssuer (e.g. Let's Encrypt via Cloudflare DNS-01, matching
# the existing cluster's pattern in ansible/install_cert_manager.yml) is a
# deliberate follow-up once this base install is confirmed working, not
# assumed here.
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
    },
    {
      name  = "cainjector.enabled"
      value = "false"
    },
    {
      name  = "startupapicheck.enabled"
      value = "false"
    },
    {
      name  = "resources.requests.cpu"
      value = "10m"
    },
    {
      name  = "resources.requests.memory"
      value = "32Mi"
    },
    {
      name  = "resources.limits.cpu"
      value = "100m"
    },
    {
      name  = "resources.limits.memory"
      value = "64Mi"
    },
    {
      name  = "webhook.resources.requests.cpu"
      value = "10m"
    },
    {
      name  = "webhook.resources.requests.memory"
      value = "32Mi"
    },
    {
      name  = "webhook.resources.limits.cpu"
      value = "100m"
    },
    {
      name  = "webhook.resources.limits.memory"
      value = "64Mi"
    }
  ]
}
