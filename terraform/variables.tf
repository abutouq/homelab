variable "PROXMOX_VE_ENDPOINT" {
  type        = string
  description = "Proxmox API endpoint URL"
}

variable "PROXMOX_VE_API_TOKEN" {
  type        = string
  description = "Proxmox API token (userid!tokenid=secret)"
  sensitive   = true
}

variable "CLOUDFLARE_API_TOKEN" {
  type        = string
  description = "Cloudflare API token scoped to Zone:DNS:Edit on homebytes.space, for certbot DNS-01 on the Teleport and Vault VMs. Ends up in Terraform state, the Proxmox snippet file, and /etc/letsencrypt/cloudflare.ini on those VMs -- keep its scope minimal."
  sensitive   = true
}

variable "CLOUDFLARE_ZONE_ID" {
  description = "Cloudflare zone ID used to create DNS records."
  type        = string
  sensitive   = true
}