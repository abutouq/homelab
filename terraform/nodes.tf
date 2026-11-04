# The Proxmox nodes. Keys use underscores so they work as attributes
# (local.nodes.pve02.name); `name` is the actual Proxmox node name.
#
# `template` is the node's plain Ubuntu cloud-init clone source: templates sit
# on node-local storage, so each node has its own. The Packer role images
# (9301-9304) exist only on external_services and are referenced directly.
# Plain data only (no resource references): big.tf builds big's template from
# this map, so referencing it back here would be a cycle.
locals {
  nodes = {
    pve = {
      name     = "pve"
      host     = "192.168.0.2"
      template = 9000
    }
    pve02 = {
      name     = "pve-02"
      host     = "192.168.0.200"
      template = 9100
    }
    external_services = {
      name     = "external-services"
      host     = "192.168.0.201"
      template = 9200
    }
    big = {
      name     = "big"
      host     = "192.168.0.202"
      template = 9400 # created by big.tf (template_big)
      # ZFS mirror of big's two extra disks (SSD + HDD), set up by bootstrap/.
      datastore = "tank-vm"
      # The HDD holding the old Immich library until bootstrap/ mirrors it into the pool.
      old_library_disk = "/dev/disk/by-id/ata-WDC_WD5000AZLX-75K2TA0_WD-WCC6Z1CAE36J"
    }
  }
}
