# Workloads pinned with nodeSelector node.kubernetes.io/environment=production
# (ase-market's chart, carried over from the old cluster) need this label.
# Separate field manager from kubernetes_labels.proxmox_topology: with the same
# manager, each resource's server-side apply would strip the other's labels.
resource "kubernetes_labels" "environment" {
  for_each      = toset(var.production_nodes)
  depends_on    = [helm_release.calico]
  api_version   = "v1"
  kind          = "Node"
  field_manager = "terraform-environment-labels"
  metadata {
    name = each.key
  }
  labels = {
    "node.kubernetes.io/environment" = "production"
  }
}
