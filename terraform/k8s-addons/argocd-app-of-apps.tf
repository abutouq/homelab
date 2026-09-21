# App of Apps: one root Application whose source.path (argocd-apps/ in
# this repo) contains this cluster's other Application manifests. ArgoCD
# auto-discovers and syncs everything it finds there, instead of each app
# being applied by hand one at a time (the pattern ../argocd/ still uses
# for the existing cluster).
#
# Applied as a raw CR via the kubectl provider — same reasoning as
# metallb.tf's IPAddressPool/L2Advertisement: the Application CRD comes
# from helm_release.argocd in this same apply, so kubernetes_manifest's
# plan-time schema validation would fail on it; kubectl_manifest skips
# that problem.
#
# abutouq/homelab is a public repo, so no repository credentials Secret is
# needed for ArgoCD to clone it read-only.
resource "kubectl_manifest" "argocd_app_of_apps" {
  depends_on = [helm_release.argocd]

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "app-of-apps"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = "main"
        path           = var.argocd_apps_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          selfHeal = true
          prune    = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })
}
