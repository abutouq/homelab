terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

# Provider credentials live in Vault (secret/homelab/*), not in terraform.tfvars.
# Auth comes from VAULT_TOKEN or ~/.vault-token, so run `vault login` before plan/apply.
# Vault itself is tf-vault-01 in main.tf: if it's down or sealed, nothing in this stack can plan.
provider "vault" {
  address = "https://vault.homebytes.space"
}

# Ephemeral: only feeds the provider block, so the Proxmox token never lands in state.
ephemeral "vault_kv_secret_v2" "proxmox" {
  mount = "secret"
  name  = "homelab/proxmox"
}

# A data source, not ephemeral: the token is rendered into the Vault/Teleport cloud-init
# snippets and zone_id into a DNS record, and neither attribute accepts ephemeral values.
data "vault_kv_secret_v2" "cloudflare" {
  mount = "secret"
  name  = "homelab/cloudflare"
}

locals {
  cloudflare = data.vault_kv_secret_v2.cloudflare.data
}

provider "proxmox" {
  endpoint  = ephemeral.vault_kv_secret_v2.proxmox.data["endpoint"]
  api_token = ephemeral.vault_kv_secret_v2.proxmox.data["api_token"]
  insecure  = true # self-signed cert, per what we saw in the audit

  ssh {
    username    = "root"
    private_key = file("~/.ssh/id_ed25519") # same key already used for root access to the nodes
  }
}

# Cloudflare provider is used to create DNS-01 challenges for certbot on the Teleport and Vault VMs. The token is scoped to Zone:DNS:Edit on homebytes.space, and ends up in Terraform state, the Proxmox snippet file, and /etc/letsencrypt/cloudflare.ini on those VMs -- keep its scope minimal.
provider "cloudflare" {
  api_token = local.cloudflare["api_token"]
}