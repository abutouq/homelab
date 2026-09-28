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
  }
}

provider "proxmox" {
  endpoint  = var.PROXMOX_VE_ENDPOINT
  api_token = var.PROXMOX_VE_API_TOKEN
  insecure  = true # self-signed cert, per what we saw in the audit

  ssh {
    username    = "root"
    private_key = file("~/.ssh/id_ed25519") # same key already used for root access to the nodes
  }
}

# Cloudflare provider is used to create DNS-01 challenges for certbot on the Teleport and Vault VMs. The token is scoped to Zone:DNS:Edit on homebytes.space, and ends up in Terraform state, the Proxmox snippet file, and /etc/letsencrypt/cloudflare.ini on those VMs -- keep its scope minimal.
provider "cloudflare" {
  api_token = var.CLOUDFLARE_API_TOKEN
}