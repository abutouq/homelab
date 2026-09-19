resource "proxmox_virtual_environment_vm" "this" {
  name      = var.vm_name
  node_name = var.node_name
  vm_id     = var.vm_id

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  initialization {
    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }
}
