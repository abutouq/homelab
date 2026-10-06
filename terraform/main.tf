# Shared static join token: registered by the control plane, used by every
# agent below. Rotating it (terraform apply -replace=random_password.teleport_join_token)
# recreates the control plane and all agents.
resource "random_password" "teleport_join_token" {
  length  = 40
  special = false
}

# Join token for the kube agent in terraform/k8s-addons. Kept apart from the shared
# node/app token above because it grants only the Kube role. Unlike that one it is NOT
# a static token in the control plane's cloud-init (changing that would mean rebuilding
# the control plane and every agent), so it must be registered once with `tctl create`,
# see terraform/README.md.
resource "random_password" "teleport_kube_token" {
  length  = 40
  special = false
}

# Published to Vault for joins outside Terraform (manual `teleport start`, Ansible,
# k8s-addons). Terraform stays the source of truth: -replace on the passwords updates this too.
resource "vault_kv_secret_v2" "teleport_join_token" {
  mount = "secret"
  name  = "homelab/teleport"
  data_json = jsonencode({
    join_token = random_password.teleport_join_token.result
    kube_token = random_password.teleport_kube_token.result
    roles      = "node,app"
    proxy      = "teleport.homebytes.space:443"
  })
}

module "tf_control_plane_01" {
  source              = "${path.root}/modules/vm"
  vm_name             = "tf-control-plane-01"
  vm_id               = 9001
  node_name           = "pve" # node .2
  template_vm_id      = 9000
  ip_address          = "192.168.0.3/24"
  gateway             = "192.168.0.1"
  ssh_public_key      = trimspace(file("~/.ssh/id_ed25519.pub"))
  teleport_role       = "agent"
  teleport_join_token = random_password.teleport_join_token.result
  # teleport.homebytes.space still resolves to .158; drop this after the DNS cutover.
  teleport_proxy_ip = split("/", module.tf_teleport_apps_01.ip_address)[0]
}

module "tf_control_plane_02" {
  source              = "${path.root}/modules/vm"
  vm_name             = "tf-control-plane-02"
  vm_id               = 9002
  node_name           = "pve-02" # node .200
  template_vm_id      = 9100
  ip_address          = "192.168.0.4/24"
  gateway             = "192.168.0.1"
  ssh_public_key      = trimspace(file("~/.ssh/id_ed25519.pub"))
  teleport_role       = "agent"
  teleport_join_token = random_password.teleport_join_token.result
  # teleport.homebytes.space still resolves to .158; drop this after the DNS cutover.
  teleport_proxy_ip = split("/", module.tf_teleport_apps_01.ip_address)[0]
}

module "tf_worker_01" {
  source              = "${path.root}/modules/vm"
  vm_name             = "tf-worker-01"
  vm_id               = 9003
  node_name           = "pve" # node .2
  template_vm_id      = 9000
  ip_address          = "192.168.0.10/24"
  gateway             = "192.168.0.1"
  ssh_public_key      = trimspace(file("~/.ssh/id_ed25519.pub"))
  teleport_role       = "agent"
  teleport_join_token = random_password.teleport_join_token.result
  # teleport.homebytes.space still resolves to .158; drop this after the DNS cutover.
  teleport_proxy_ip = split("/", module.tf_teleport_apps_01.ip_address)[0]
}

module "tf_worker_02" {
  source              = "${path.root}/modules/vm"
  vm_name             = "tf-worker-02"
  vm_id               = 9004
  node_name           = "pve-02" # node .200
  template_vm_id      = 9100
  ip_address          = "192.168.0.11/24"
  gateway             = "192.168.0.1"
  ssh_public_key      = trimspace(file("~/.ssh/id_ed25519.pub"))
  teleport_role       = "agent"
  teleport_join_token = random_password.teleport_join_token.result
  # teleport.homebytes.space still resolves to .158; drop this after the DNS cutover.
  teleport_proxy_ip = split("/", module.tf_teleport_apps_01.ip_address)[0]
}

module "tf_external_services_01" {
  source              = "${path.root}/modules/vm"
  vm_name             = "tf-external-services-01"
  vm_id               = 9005
  node_name           = "external-services" # node .201
  template_vm_id      = 9200
  ip_address          = "192.168.0.20/24"
  gateway             = "192.168.0.1"
  ssh_public_key      = trimspace(file("~/.ssh/id_ed25519.pub"))
  teleport_role       = "agent"
  teleport_join_token = random_password.teleport_join_token.result
  # teleport.homebytes.space still resolves to .158; drop this after the DNS cutover.
  teleport_proxy_ip = split("/", module.tf_teleport_apps_01.ip_address)[0]
}

module "tf_teleport_apps_01" {
  source               = "${path.root}/modules/vm"
  vm_name              = "tf-teleport-apps-01"
  vm_id                = 9006
  node_name            = "external-services" # node .201
  template_vm_id       = 9302                # Packer: packer/teleport.pkr.hcl
  image_baked          = true
  ip_address           = "192.168.0.21/24"
  gateway              = "192.168.0.1"
  ssh_public_key       = trimspace(file("~/.ssh/id_ed25519.pub"))
  teleport_role        = "control_plane"
  teleport_join_token  = random_password.teleport_join_token.result
  cloudflare_api_token = local.cloudflare["api_token"]
}

module "tf_vault_01" {
  source              = "${path.root}/modules/vm"
  vm_name             = "tf-vault-01"
  vm_id               = 9007
  node_name           = "external-services" # node .201
  template_vm_id      = 9301                # Packer: packer/vault.pkr.hcl
  image_baked         = true
  ip_address          = "192.168.0.22/24"
  gateway             = "192.168.0.1"
  ssh_public_key      = trimspace(file("~/.ssh/id_ed25519.pub"))
  vault_role          = "server"
  teleport_role       = "agent"
  teleport_join_token = random_password.teleport_join_token.result
  # teleport.homebytes.space still resolves to .158; drop this after the DNS cutover.
  teleport_proxy_ip    = split("/", module.tf_teleport_apps_01.ip_address)[0]
  cloudflare_api_token = local.cloudflare["api_token"]
}

module "tf_grafana_01" {
  source              = "${path.root}/modules/vm"
  vm_name             = "tf-grafana-01"
  vm_id               = 9008
  node_name           = "external-services" # node .201
  template_vm_id      = 9303                # Packer: packer/grafana.pkr.hcl
  image_baked         = true
  ip_address          = "192.168.0.23/24"
  gateway             = "192.168.0.1"
  ssh_public_key      = trimspace(file("~/.ssh/id_ed25519.pub"))
  grafana_role        = "server"
  teleport_role       = "agent"
  teleport_join_token = random_password.teleport_join_token.result
  # teleport.homebytes.space still resolves to .158; drop this after the DNS cutover.
  teleport_proxy_ip = split("/", module.tf_teleport_apps_01.ip_address)[0]
}

resource "cloudflare_dns_record" "vault" {
  zone_id = local.cloudflare["zone_id"]
  name    = "vault.homebytes.space"
  type    = "A"
  content = split("/", module.tf_vault_01.ip_address)[0]
  ttl     = 300
  proxied = false
}
