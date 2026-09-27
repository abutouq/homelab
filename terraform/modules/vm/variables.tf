variable "vm_name" {
  type = string
}
variable "vm_id" {
  type = number
}
variable "node_name" {
  type = string
}
variable "template_vm_id" {
  type = number
}
variable "ip_address" {
  type = string
}
variable "gateway" {
  type = string
}
variable "ssh_public_key" {
  type = string
}
variable "teleport_role" {
  type        = string
  default     = "none"
  description = "Teleport role to configure via cloud-init on first boot: \"none\" (nothing installed), \"control_plane\" (auth+proxy+ssh, fresh CA -- this is the actual Teleport cluster), or \"agent\" (joins an existing control plane -- not implemented yet)."
  validation {
    condition     = contains(["none", "control_plane", "agent"], var.teleport_role)
    error_message = "teleport_role must be one of: none, control_plane, agent."
  }
}
variable "teleport_cluster_name" {
  type        = string
  default     = "teleport.homebytes.space"
  description = "Only used when teleport_role = \"control_plane\"."
}
variable "vault_role" {
  type        = string
  default     = "none"
  description = "Vault role to configure via cloud-init on first boot: \"none\" (nothing installed) or \"server\" (single-node raft Vault server with a Let's Encrypt cert, reachable directly on the LAN at https://<vault_domain>:8200). Init/unseal stays manual."
  validation {
    condition     = contains(["none", "server"], var.vault_role)
    error_message = "vault_role must be one of: none, server."
  }
}
variable "vault_domain" {
  type        = string
  default     = "vault.homebytes.space"
  description = "Only used when vault_role = \"server\". Needs a DNS A record pointing at this VM's IP -- certbot's DNS-01 challenge doesn't create one."
}
variable "cloudflare_api_token" {
  type        = string
  default     = null
  sensitive   = true
  description = "Cloudflare token (Zone:DNS:Edit on homebytes.space) for certbot's DNS-01 challenge and renewals. Required for teleport_role = \"control_plane\" and vault_role = \"server\"."
}
variable "acme_staging" {
  type        = bool
  default     = false
  description = "Use Let's Encrypt staging (untrusted certs, no rate limits) -- flip on while iterating on VM recreation, since every recreate issues a new cert."
}