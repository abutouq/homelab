variable "kubeconfig_path" {
  type        = string
  description = "Path to the new cluster's admin kubeconfig, fetched by ansible/bootstrap_new_cluster.yml"
  default     = "~/.kube/config-new-cluster"
}

variable "pod_cidr" {
  type        = string
  description = "Pod network CIDR — must exactly match --pod-network-cidr passed to kubeadm init"
  default     = "10.100.0.0/16"
}

variable "metallb_pool" {
  type        = list(string)
  description = "IP range MetalLB hands out for this cluster's LoadBalancer services. Must not overlap the EXISTING cluster's MetalLB pool (192.168.0.200-250, see k8s-services/metallb-config.yaml)."
  default     = ["192.168.0.30-192.168.0.69"]
}

variable "gitops_repo_url" {
  type        = string
  description = "Git repo ArgoCD's app-of-apps watches for this cluster's Application manifests"
  default     = "https://github.com/abutouq/homelab.git"
}

variable "argocd_apps_path" {
  type        = string
  description = "Path within gitops_repo_url holding this cluster's ArgoCD Application manifests. Deliberately separate from ../argocd/ at repo root, which belongs to the EXISTING cluster's manually-applied Applications."
  default     = "argocd-apps"
}
