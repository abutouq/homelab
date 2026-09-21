# argocd-apps

Application manifests for the **new**, Terraform/kubeadm-provisioned HA cluster (see `../terraform/`), auto-discovered and synced by the "app of apps" root Application (`terraform/k8s-addons/argocd-app-of-apps.tf`).

Drop an `Application` YAML here and its root app will pick it up automatically on the next sync — no manual `kubectl apply` needed.

This is deliberately separate from `../argocd/` at the repo root, which holds the **existing** cluster's Applications and is still applied manually one at a time.
