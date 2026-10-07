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

variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API the CSI controller talks to"
  default     = "https://192.168.0.2:8006/api2/json"
}

variable "proxmox_region" {
  type        = string
  description = "Proxmox cluster name, used as topology.kubernetes.io/region"
  default     = "prx-cluster-01"
}

variable "proxmox_node_zones" {
  type        = map(string)
  description = "K8s node name -> Proxmox host it runs on (topology.kubernetes.io/zone). Must match node_name in ../main.tf."
  default = {
    "tf-control-plane-01" = "pve"
    "tf-control-plane-02" = "pve-02"
    "tf-worker-01"        = "pve"
    "tf-worker-02"        = "pve-02"
  }
}

variable "kubernetes_api_url" {
  type        = string
  description = "This cluster's API (kube-vip VIP), as reached from Vault for TokenReview"
  default     = "https://192.168.0.19:6443"
}
