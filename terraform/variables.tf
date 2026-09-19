variable "PROXMOX_VE_ENDPOINT" {
  type        = string
  description = "Proxmox API endpoint URL"
}

variable "PROXMOX_VE_API_TOKEN" {
  type        = string
  description = "Proxmox API token (userid!tokenid=secret)"
  sensitive   = true
}
