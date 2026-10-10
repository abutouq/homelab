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
  description = "Teleport role to configure via cloud-init on first boot (composes with vault_role): \"none\" (nothing installed), \"control_plane\" (auth+proxy+ssh, fresh CA -- this is the actual Teleport cluster), or \"agent\" (ssh_service agent that joins the control plane with teleport_join_token)."
  validation {
    condition     = contains(["none", "control_plane", "agent"], var.teleport_role)
    error_message = "teleport_role must be one of: none, control_plane, agent."
  }
}
variable "teleport_join_token" {
  type        = string
  default     = null
  sensitive   = true
  description = "Static node/app join token. The control plane registers it; agents use it to join at first boot."
}
variable "teleport_proxy_ip" {
  type        = string
  default     = null
  description = "Agents only: pin teleport_cluster_name to this IP in /etc/hosts. Needed until the public DNS record points at the control plane; set to null after cutover."
}
variable "teleport_cluster_name" {
  type        = string
  default     = "teleport.homebytes.space"
  description = "Only used when teleport_role = \"control_plane\"."
}
variable "vault_role" {
  type        = string
  default     = "none"
  description = "Vault role to configure via cloud-init on first boot: \"none\" (nothing installed) or \"server\" (single-node raft Vault server with a Let's Encrypt cert, reachable directly on the LAN at https://<vault_domain> (port 443)). Init/unseal stays manual."
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

variable "image_baked" {
  type        = bool
  default     = false
  description = "True when template_vm_id is a Packer image with Teleport/Vault/Grafana/certbot already installed (packer/*.pkr.hcl). cloud-init then skips package installs. The vault, teleport control_plane and grafana roles require it."
}

variable "grafana_role" {
  type        = string
  default     = "none"
  description = "Grafana role to configure via cloud-init on first boot: \"none\" or \"server\" (starts the Grafana server baked into the image, on port 3000)."
  validation {
    condition     = contains(["none", "server"], var.grafana_role)
    error_message = "grafana_role must be one of: none, server."
  }
}

variable "memory_mb" {
  type        = number
  default     = null
  description = "RAM in MB; null keeps the template's 2 GB. Changing it reboots the VM."
}

variable "cpu_type" {
  type        = string
  default     = null
  description = "Proxmox CPU type, e.g. \"x86-64-v3\" (needs AVX2 on the host: pve and pve-02 yes, external-services no) or \"host\". null keeps the template's default (kvm64). Changing it reboots the VM."
}

variable "cpu_cores" {
  type        = number
  default     = 2
  description = "Only applied together with cpu_type; matches the templates' 2 cores."
}

variable "grafana_admin_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Grafana admin password (grafana role). Applied when Grafana first creates its database, i.e. on a fresh VM."
}

variable "grafana_dashboards" {
  type        = map(string)
  default     = {}
  description = "Dashboard files for the grafana role: relative path (subdirectory = Grafana folder) -> base64 JSON."
}

variable "grafana_root_url" {
  type        = string
  default     = "https://grafana.teleport.homebytes.space/"
  description = "Public URL Grafana is browsed at (grafana role): the Teleport app served by the kube agent. Must match, or logins fail with \"origin not allowed\"."
}

variable "prometheus_k8s" {
  type = object({
    api_server = string # host:port of the K8s API (kube-vip VIP)
    token      = string
    ca_crt     = string
  })
  default     = null
  sensitive   = true
  description = "grafana role: read-only K8s identity (from k8s-addons via Vault) for scraping the cluster through the API proxy. null = no cluster jobs."
}

variable "prometheus_node_targets" {
  type        = list(string)
  default     = []
  description = "grafana role: host:port node-exporter targets scraped directly (e.g. the Proxmox hosts)."
}
