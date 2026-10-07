# Lightweight install: cainjector stays ENABLED -- cert-manager's own
# webhook needs it to inject its CA bundle into the webhook configuration;
# without it every cert-manager resource is rejected with "x509: certificate
# signed by unknown authority" (hit 2026-10-07). startupapicheck disabled (a one-shot Job that just probes the
# webhook post-install; skipping it saves a pod, not a capability), and
# small explicit resource requests/limits so the remaining two components
# (controller, webhook) are scheduled predictably instead of BestEffort
# with no bound at all (the chart's default).
#
# letsencrypt-prod (below) matches the old cluster's issuer: Cloudflare DNS-01,
# so it works for names that point at private LAN IPs.
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
      value = "true"
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

# Cloudflare token for DNS-01, synced from Vault by ESO (external-secrets.tf).
resource "kubectl_manifest" "cloudflare_api_token" {
  depends_on = [helm_release.cert_manager, kubectl_manifest.vault_store]
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = "cloudflare-api-token", namespace = "cert-manager" }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { kind = "ClusterSecretStore", name = "vault" }
      target          = { name = "cloudflare-api-token" }
      data = [{
        secretKey = "api-token"
        remoteRef = { key = "homelab/cloudflare", property = "api_token" }
      }]
    }
  })
}

resource "kubectl_manifest" "letsencrypt_prod" {
  depends_on = [kubectl_manifest.cloudflare_api_token]
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = "letsencrypt-prod" }
    spec = {
      acme = {
        server              = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = { name = "letsencrypt-prod-account-key" }
        solvers = [{
          dns01 = {
            cloudflare = {
              apiTokenSecretRef = { name = "cloudflare-api-token", key = "api-token" }
            }
          }
        }]
      }
    }
  })
}
