# Proxmox CSI (sergelogvinov/proxmox-csi-plugin): PVCs become Proxmox disks,
# hot-plugged into the VM running the pod. local-lvm is per-host storage, so a
# volume lives on one Proxmox node and its pods are pinned to that node's VMs
# via the topology labels below.

# Node plugin mounts host devices, so the namespace must allow privileged pods.
resource "kubernetes_namespace" "proxmox_csi" {
  depends_on = [helm_release.calico]
  metadata {
    name = "csi-proxmox"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

# The plugin locates each node's VM by these labels (region = Proxmox cluster,
# zone = Proxmox host). Without Proxmox CCM nothing sets them automatically.
resource "kubernetes_labels" "proxmox_topology" {
  for_each    = var.proxmox_node_zones
  depends_on  = [helm_release.calico]
  api_version = "v1"
  kind        = "Node"
  metadata {
    name = each.key
  }
  labels = {
    "topology.kubernetes.io/region" = var.proxmox_region
    "topology.kubernetes.io/zone"   = each.value
  }
}

resource "helm_release" "proxmox_csi" {
  depends_on = [kubernetes_labels.proxmox_topology]
  name       = "proxmox-csi-plugin"
  repository = "oci://ghcr.io/sergelogvinov/charts"
  chart      = "proxmox-csi-plugin"
  namespace  = kubernetes_namespace.proxmox_csi.metadata[0].name

  values = [yamlencode({
    config = {
      clusters = [{
        url      = var.proxmox_api_url
        insecure = true # Proxmox's self-signed API cert
        token_id = var.proxmox_csi_token_id
        region   = var.proxmox_region
      }]
    }
    storageClass = [{
      name          = "proxmox-lvm"
      storage       = "local-lvm"
      reclaimPolicy = "Delete"
      fstype        = "ext4"
      annotations = {
        "storageclass.kubernetes.io/is-default-class" = "true"
      }
    }]
  })]

  set_sensitive = [
    {
      name  = "config.clusters[0].token_secret"
      value = var.proxmox_csi_token_secret
    }
  ]
}
