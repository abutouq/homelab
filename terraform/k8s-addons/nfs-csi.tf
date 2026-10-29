# csi-driver-nfs: PVCs on the "nas-nfs" StorageClass become directories under
# /srv/share/k8s on tf-nas-01 (192.168.0.26), i.e. on big's ZFS mirror. Unlike
# proxmox-lvm these are ReadWriteMany and not pinned to one Proxmox host, so
# use it for data that several pods share or that should outlive a node.
# The export is limited to the cluster's node IPs (nfs_clients in ../big.tf);
# the driver mounts from its own container, so nodes need no nfs-common.
resource "helm_release" "csi_driver_nfs" {
  depends_on = [helm_release.calico]
  name       = "csi-driver-nfs"
  repository = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts"
  chart      = "csi-driver-nfs"
  version    = "4.13.6"
  namespace  = "kube-system"

  values = [yamlencode({
    storageClass = {
      create = true
      name   = "nas-nfs"
      parameters = {
        server = "192.168.0.26"
        share  = "/srv/share/k8s"
        # Deleting a PVC renames its directory to archived-<name> instead of erasing it.
        onDelete = "archive"
      }
      reclaimPolicy     = "Delete"
      volumeBindingMode = "Immediate"
      mountOptions      = ["nfsvers=4.1", "hard"]
    }
  })]
}
