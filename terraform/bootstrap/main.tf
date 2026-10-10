# Proxmox bootstrap: everything that must exist before the main stack
# (../) can even plan — its Proxmox API token, the roles behind it, the other
# service users (Packer, Proxmox CSI) — plus host-level setup on the nodes.
#
# Needs only root SSH to the nodes (~/.ssh/id_ed25519) and a Vault login
# (`vault login`, VAULT_ADDR below); no Proxmox API token, since creating
# those is its job. Every step is idempotent and re-runs when its script
# changes. Run order for a full build: this stack, then ../, then
# ../k8s-addons.

locals {
  vault_addr = "https://vault.homebytes.space"

  proxmox_hosts = {
    pve               = "192.168.0.2"
    pve-02            = "192.168.0.200"
    external-services = "192.168.0.201"
  }
  # Any node works for cluster-wide config (/etc/pve is shared).
  api_host = local.proxmox_hosts["pve"]

  roles = {
    # The main stack's provider (../provider.tf).
    TerraformProv = [
      "Datastore.Allocate", # uploading cloud-init snippets
      "Datastore.AllocateSpace", "Datastore.Audit", "Pool.Allocate", "SDN.Use",
      "VM.Allocate", "VM.Audit", "VM.Clone", "VM.Config.CDROM", "VM.Config.CPU",
      "VM.Config.Cloudinit", "VM.Config.Disk", "VM.Config.HWType", "VM.Config.Memory",
      "VM.Config.Network", "VM.Config.Options", "VM.PowerMgmt",
    ]
    # Image builds (../../packer).
    Packer = [
      "Datastore.AllocateSpace", "Datastore.AllocateTemplate", "Datastore.Audit",
      "Pool.Audit", "SDN.Use", "Sys.Audit", "Sys.Console", "Sys.Modify",
      "VM.Allocate", "VM.Audit", "VM.Clone", "VM.Config.CDROM", "VM.Config.CPU",
      "VM.Config.Cloudinit", "VM.Config.Disk", "VM.Config.HWType", "VM.Config.Memory",
      "VM.Config.Network", "VM.Config.Options", "VM.Console", "VM.GuestAgent.Audit",
      "VM.PowerMgmt",
    ]
    # Proxmox CSI plugin (../k8s-addons/proxmox-csi.tf): create/attach/resize disks only.
    CSI = ["VM.Audit", "VM.Config.Disk", "Datastore.Allocate", "Datastore.AllocateSpace", "Datastore.Audit"]
  }

  # Service users: role (ACL on /), API token name, and the Vault entry that
  # holds the token for whoever consumes it. Every entry gets token_id and
  # token_secret; the main stack's also gets endpoint + api_token, the
  # format ../provider.tf reads.
  users = {
    "terraform@pve"      = { role = "TerraformProv", token = "provider", vault = "homelab/proxmox", comment = "Terraform main stack (bpg/proxmox)" }
    "packer@pve"         = { role = "Packer", token = "packer", vault = "homelab/packer", comment = "Packer image builds" }
    "kubernetes-csi@pve" = { role = "CSI", token = "csi", vault = "homelab/proxmox-csi", comment = "Proxmox CSI plugin (tf-managed K8s cluster)" }
  }

  host_script = <<-EOT
    set -e
    # node-exporter, scraped by Prometheus on tf-grafana-01 (proxmox-hosts job)
    if ! dpkg -s prometheus-node-exporter >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq prometheus-node-exporter
    fi
    systemctl enable --now prometheus-node-exporter
  EOT

  cluster_script = join("\n", concat([<<-EOT
    set -e
    # 'snippets' on the cluster-wide 'local' storage: holds the VMs' cloud-init files
    cur=$(pvesh get /storage/local --output-format json | jq -r .content)
    case ",$cur," in *,snippets,*) ;; *) pvesm set local --content "$cur,snippets" ;; esac

    role() { # role <id> <privs>: create, or reset to exactly these privileges
      if pveum role list --output-format json | jq -e --arg r "$1" '.[] | select(.roleid==$r)' >/dev/null
      then pveum role modify "$1" -privs "$2"
      else pveum role add "$1" -privs "$2"; fi
    }
    user() { # user <id> <role> <comment>: create if missing, grant role on /
      if ! pveum user list --output-format json | jq -e --arg u "$1" '.[] | select(.userid==$u)' >/dev/null
      then pveum user add "$1" --comment "$3"; fi
      pveum aclmod / -user "$1" -role "$2"
    }
  EOT
    ],
    [for id, privs in local.roles : "role ${id} \"${join(",", privs)}\""],
    [for id, u in local.users : "user ${id} ${u.role} \"${u.comment}\""],
  ))
}

resource "terraform_data" "host" {
  for_each         = local.proxmox_hosts
  triggers_replace = sha256(local.host_script)

  connection {
    type        = "ssh"
    host        = each.value
    user        = "root"
    private_key = file("~/.ssh/id_ed25519")
  }

  provisioner "remote-exec" {
    inline = [local.host_script]
  }
}

resource "terraform_data" "cluster" {
  triggers_replace = sha256(local.cluster_script)

  connection {
    type        = "ssh"
    host        = local.api_host
    user        = "root"
    private_key = file("~/.ssh/id_ed25519")
  }

  provisioner "remote-exec" {
    inline = [local.cluster_script]
  }
}

# A Proxmox token's secret is shown only once, at creation, so it goes
# straight from pveum into Vault and never through Terraform state. Skipped
# when the Vault entry already exists. To rotate one:
#   vault kv delete secret/<entry>
#   terraform apply -replace='terraform_data.token["<user>"]'
resource "terraform_data" "token" {
  for_each   = local.users
  depends_on = [terraform_data.cluster]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      VAULT_ADDR = local.vault_addr
      USER_ID    = each.key
      TOKEN      = each.value.token
      ENTRY      = each.value.vault
      ENDPOINT   = "https://${local.api_host}:8006/"
    }
    command = <<-EOT
      set -euo pipefail
      if vault kv get -mount=secret "$ENTRY" >/dev/null 2>&1; then
        echo "$USER_ID: token already in Vault ($ENTRY), nothing to do"; exit 0
      fi
      SECRET=$(ssh -o BatchMode=yes root@${local.api_host} \
        "pveum user token remove $USER_ID $TOKEN >/dev/null 2>&1 || true
         pveum user token add $USER_ID $TOKEN -privsep 0 --output-format json" | jq -r .value)
      printf %s "$SECRET" | vault kv put -mount=secret "$ENTRY" \
        token_id="$USER_ID!$TOKEN" endpoint="$ENDPOINT" token_secret=- >/dev/null
      # The main stack's provider reads one combined "user!token=secret" value.
      if [ "$ENTRY" = "homelab/proxmox" ]; then
        printf %s "$USER_ID!$TOKEN=$SECRET" | vault kv patch -mount=secret "$ENTRY" api_token=- >/dev/null
      fi
      unset SECRET
      echo "$USER_ID: token created and stored in Vault ($ENTRY)"
    EOT
  }
}
