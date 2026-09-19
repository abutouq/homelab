terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

provider "proxmox" {
  endpoint  = var.PROXMOX_VE_ENDPOINT
  api_token = var.PROXMOX_VE_API_TOKEN
  insecure  = true # self-signed cert, per what we saw in the audit
}
