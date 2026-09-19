terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# All three providers point at the new cluster's admin kubeconfig, produced
# by the kubeadm bootstrap playbook (ansible/bootstrap_new_cluster.yml).
# This config cannot apply successfully until that kubeconfig exists.

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# gavinbunney/kubectl is used only for the couple of CRs (MetalLB's
# IPAddressPool/L2Advertisement) that hashicorp/kubernetes' kubernetes_manifest
# can't apply reliably in the same apply as the CRD that defines them.
provider "kubectl" {
  config_path      = var.kubeconfig_path
  load_config_file = true
}
