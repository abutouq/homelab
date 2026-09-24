locals {
  teleport_cloud_init_content = (
    var.teleport_role == "control_plane" ? templatefile("${path.module}/templates/teleport-control-plane-cloud-init.yaml.tftpl", {
      username       = "ubuntu"
      ssh_public_key = var.ssh_public_key
      nodename       = var.vm_name
      cluster_name   = var.teleport_cluster_name
    }) :
    var.teleport_role == "agent" ? templatefile("${path.module}/templates/teleport-agent-cloud-init.yaml.tftpl", {
      username       = "ubuntu"
      ssh_public_key = var.ssh_public_key
    }) :
    ""
  )
}

resource "proxmox_virtual_environment_file" "teleport_cloud_init" {
  count        = var.teleport_role != "none" ? 1 : 0
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data      = local.teleport_cloud_init_content
    file_name = "teleport-cloud-init-${var.vm_name}.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.vm_name
  node_name = var.node_name
  vm_id     = var.vm_id

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  initialization {
    dynamic "user_account" {
      for_each = var.teleport_role == "none" ? [1] : []
      content {
        username = "ubuntu"
        keys     = [var.ssh_public_key]
      }
    }

    user_data_file_id = var.teleport_role != "none" ? proxmox_virtual_environment_file.teleport_cloud_init[0].id : null

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }
}
