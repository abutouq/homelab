# External Secrets Operator: syncs Vault (vault.homebytes.space, kv v2 mount
# "secret") into Kubernetes Secrets. Apps declare ExternalSecrets against the
# "vault" ClusterSecretStore; rotating a secret is just `vault kv put`.
#
# Vault authenticates ESO with its Kubernetes auth method: ESO presents its
# service account token, Vault checks it against this cluster's API using the
# vault-auth reviewer account below.

# --- Reviewer account Vault uses to validate service account tokens ----------
resource "kubernetes_service_account" "vault_auth" {
  metadata {
    name      = "vault-auth"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_binding" "vault_auth" {
  metadata {
    name = "vault-auth-tokenreview"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_auth.metadata[0].name
    namespace = "kube-system"
  }
}

# Long-lived token: Vault keeps using it for TokenReview calls.
resource "kubernetes_secret" "vault_auth" {
  metadata {
    name      = "vault-auth-token"
    namespace = "kube-system"
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.vault_auth.metadata[0].name
    }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

# --- Vault side ---------------------------------------------------------------
resource "vault_auth_backend" "kubernetes" {
  type        = "kubernetes"
  path        = "kubernetes-proxmox-homelab"
  description = "Service accounts of the tf-managed proxmox-homelab cluster"
}

resource "vault_kubernetes_auth_backend_config" "this" {
  backend                = vault_auth_backend.kubernetes.path
  kubernetes_host        = var.kubernetes_api_url
  kubernetes_ca_cert     = kubernetes_secret.vault_auth.data["ca.crt"]
  token_reviewer_jwt     = kubernetes_secret.vault_auth.data["token"]
  disable_local_ca_jwt   = true # Vault runs outside this cluster
  disable_iss_validation = true
}

# Read-only: what ESO may pull into this cluster.
resource "vault_policy" "external_secrets" {
  name   = "external-secrets-proxmox-homelab"
  policy = <<-EOT
    path "secret/data/apps/*" {
      capabilities = ["read"]
    }
    path "secret/data/homelab/cloudflare" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "external_secrets" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "external-secrets"
  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["external-secrets"]
  token_policies                   = [vault_policy.external_secrets.name]
  token_ttl                        = 3600
}

# --- Operator -----------------------------------------------------------------
resource "helm_release" "external_secrets" {
  depends_on       = [helm_release.calico]
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]
}

# Cluster-wide store every namespace's ExternalSecrets can reference.
resource "kubectl_manifest" "vault_store" {
  depends_on = [helm_release.external_secrets, vault_kubernetes_auth_backend_role.external_secrets]
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata   = { name = "vault" }
    spec = {
      provider = {
        vault = {
          server  = "https://vault.homebytes.space"
          path    = "secret"
          version = "v2"
          auth = {
            kubernetes = {
              mountPath = vault_auth_backend.kubernetes.path
              role      = vault_kubernetes_auth_backend_role.external_secrets.role_name
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  })
}
