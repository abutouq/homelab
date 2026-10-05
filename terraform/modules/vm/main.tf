locals {
  # Role parts are merged into one multi-part user-data, so roles compose
  # (e.g. a Vault server that is also a Teleport agent).
  role_parts = compact([
    var.teleport_role == "control_plane" ? "teleport-control-plane.yaml.tftpl" : "",
    var.teleport_role == "agent" ? "teleport-agent.yaml.tftpl" : "",
    var.vault_role == "server" ? "vault-server.yaml.tftpl" : "",
    var.grafana_role == "server" ? "grafana.yaml.tftpl" : "",
  ])
  has_role   = length(local.role_parts) > 0
  needs_acme = var.teleport_role == "control_plane" || var.vault_role == "server"

  # Templates ignore vars they don't reference, so every part gets the same set.
  template_vars = {
    username             = "ubuntu"
    ssh_public_key       = var.ssh_public_key
    nodename             = var.vm_name
    cluster_name         = var.teleport_cluster_name
    teleport_join_token  = var.teleport_join_token == null ? "" : var.teleport_join_token
    teleport_proxy_ip    = var.teleport_proxy_ip == null ? "" : var.teleport_proxy_ip
    vault_domain         = var.vault_domain
    vault_ip             = split("/", var.ip_address)[0]
    cloudflare_api_token = var.cloudflare_api_token == null ? "" : var.cloudflare_api_token
    acme_staging         = var.acme_staging
    image_baked          = var.image_baked
  }
}

data "cloudinit_config" "this" {
  count         = local.has_role ? 1 : 0
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content      = templatefile("${path.module}/templates/base.yaml.tftpl", local.template_vars)
  }

  dynamic "part" {
    for_each = local.role_parts
    content {
      content_type = "text/cloud-config"
      content      = templatefile("${path.module}/templates/${part.value}", local.template_vars)
      # Append lists (packages, write_files, runcmd) across parts instead of
      # letting a later part replace an earlier one's.
      merge_type = "list(append)+dict(no_replace,recurse_list)+str()"
    }
  }
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  count        = local.has_role ? 1 : 0
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data      = sensitive(data.cloudinit_config.this[0].rendered)
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
    # A custom user-data file replaces the generated one; base.yaml.tftpl
    # creates the ubuntu user in that case.
    dynamic "user_account" {
      for_each = local.has_role ? [] : [1]
      content {
        username = "ubuntu"
        keys     = [var.ssh_public_key]
      }
    }

    user_data_file_id = local.has_role ? proxmox_virtual_environment_file.cloud_init[0].id : null

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }

  lifecycle {
    # Disks come from the template; after that, Proxmox CSI hot-plugs PV disks
    # that Terraform must not try to detach.
    ignore_changes = [disk]

    precondition {
      condition     = !local.needs_acme || nonsensitive(var.cloudflare_api_token != null)
      error_message = "cloudflare_api_token is required when teleport_role = \"control_plane\" or vault_role = \"server\" (certbot DNS-01)."
    }
    precondition {
      condition     = var.image_baked || (var.vault_role == "none" && var.grafana_role == "none" && var.teleport_role != "control_plane")
      error_message = "The vault, grafana and teleport control_plane roles need a Packer image (image_baked = true); their cloud-init no longer installs packages."
    }
    precondition {
      condition     = var.teleport_role == "none" || nonsensitive(var.teleport_join_token != null)
      error_message = "teleport_join_token is required when teleport_role is \"control_plane\" or \"agent\"."
    }
  }
}
