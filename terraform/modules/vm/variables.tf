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
