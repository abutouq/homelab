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
    # grafana role
    grafana_admin_password = var.grafana_admin_password == null ? "" : var.grafana_admin_password
    grafana_dashboards     = var.grafana_dashboards
    grafana_root_url       = var.grafana_root_url
    grafana_public_host    = regex("^https?://([^/:]+)", var.grafana_root_url)[0]
    vm_ip                  = split("/", var.ip_address)[0]
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

  # Pinned rather than inherited: Packer's clone builder defaults templates to the
  # emulated LSI controller, and guests on it froze for good when the node's SSD
  # stalled on writes (2026-10-06), while virtio-scsi guests recovered.
  scsi_hardware = "virtio-scsi-pci"

  # Omitted unless cpu_type is set, so other VMs keep the template's CPU. The
  # default (kvm64) hides SSE4.2/AVX/AVX2 from guests; binaries built for
  # x86-64-v3 (e.g. the claude CLI) then spin forever instead of starting.
  # cores is restated because the provider's cpu block defaults it to 1.
  dynamic "cpu" {
    for_each = var.cpu_type == null ? [] : [1]
    content {
      type  = var.cpu_type
      cores = var.cpu_cores
    }
  }

  # Omitted unless set, so other VMs keep the template's 2 GB.
  dynamic "memory" {
    for_each = var.memory_mb == null ? [] : [1]
    content {
      dedicated = var.memory_mb
    }
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
      condition     = var.grafana_role == "none" || nonsensitive(var.grafana_admin_password != null)
      error_message = "grafana_admin_password is required when grafana_role = \"server\" (otherwise Grafana keeps admin/admin)."
    }
    precondition {
      condition     = var.teleport_role == "none" || nonsensitive(var.teleport_join_token != null)
      error_message = "teleport_join_token is required when teleport_role is \"control_plane\" or \"agent\"."
    }
  }
}
