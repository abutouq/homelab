locals {
  # One VM gets exactly one cloud-init user-data file, so roles don't compose
  # yet -- the precondition below rejects setting both instead of silently
  # dropping one.
  cloud_init_template = (
    var.teleport_role == "control_plane" ? "teleport-control-plane-cloud-init.yaml.tftpl" :
    var.teleport_role == "agent" ? "teleport-agent-cloud-init.yaml.tftpl" :
    var.vault_role == "server" ? "vault-cloud-init.tftpl" :
    null
  )
  needs_acme = var.teleport_role == "control_plane" || var.vault_role == "server"
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  count        = local.cloud_init_template == null ? 0 : 1
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    # Templates ignore vars they don't reference, so every role gets the same set.
    data = templatefile("${path.module}/templates/${local.cloud_init_template}", {
      username             = "ubuntu"
      ssh_public_key       = var.ssh_public_key
      nodename             = var.vm_name
      cluster_name         = var.teleport_cluster_name
      vault_domain         = var.vault_domain
      vault_ip             = split("/", var.ip_address)[0]
      cloudflare_api_token = coalesce(var.cloudflare_api_token, "")
      acme_staging         = var.acme_staging
    })
    file_name = "cloud-init-${var.vm_name}.yaml"
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
    # A custom user-data file replaces the generated one, so each template
    # creates the ubuntu user itself.
    dynamic "user_account" {
      for_each = local.cloud_init_template == null ? [1] : []
      content {
        username = "ubuntu"
        keys     = [var.ssh_public_key]
      }
    }

    user_data_file_id = local.cloud_init_template == null ? null : proxmox_virtual_environment_file.cloud_init[0].id

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.teleport_role == "none" || var.vault_role == "none"
      error_message = "teleport_role and vault_role can't both be set on one VM yet -- only one cloud-init user-data file is attached."
    }
    precondition {
      condition     = !local.needs_acme || nonsensitive(var.cloudflare_api_token != null)
      error_message = "cloudflare_api_token is required when teleport_role = \"control_plane\" or vault_role = \"server\" (certbot DNS-01)."
    }
  }
}
