# Shared static join token: registered by the control plane, used by every
# agent below. Rotating it (terraform apply -replace=random_password.teleport_join_token)
# recreates the control plane and all agents.
resource "random_password" "teleport_join_token" {
  length  = 40
  special = false
}

# Join token for the kube agent in terraform/k8s-addons. Kept apart from the shared
# node/app token above because it grants only what that agent runs (Kube, App). Unlike that one it is NOT
# a static token in the control plane's cloud-init (changing that would rebuild the
# control plane with a new CA, orphaning every agent), so it is registered once per
# control-plane build with `tctl create`, see terraform/README.md.
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
  # 2 GB ran out of memory (2026-10-07: installing ESO froze one, and with only
  # 2 etcd members that took the whole cluster down).
  memory_mb = 3072
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
  # 2 GB ran out of memory (2026-10-07: installing ESO froze one, and with only
  # 2 etcd members that took the whole cluster down).
  memory_mb = 3072
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
  # kvm64 hides AVX2 etc.; kids-app's claude CLI spins forever without them.
  cpu_type = "x86-64-v3"
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
  # kvm64 hides AVX2 etc.; kids-app's claude CLI spins forever without them.
  cpu_type = "x86-64-v3"
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

# Teleport's public names, cut over from the old server (192.168.0.158) to
# tf-teleport-apps-01. The wildcard serves Teleport app access (<app>.teleport...).
locals {
  teleport_dns_names = {
    teleport          = "teleport.homebytes.space"
    teleport_wildcard = "*.teleport.homebytes.space"
  }
}

resource "cloudflare_dns_record" "teleport" {
  for_each = local.teleport_dns_names
  zone_id  = local.cloudflare["zone_id"]
  name     = each.value
  type     = "A"
  content  = split("/", module.tf_teleport_apps_01.ip_address)[0]
  ttl      = 300
  proxied  = false
}

# The records were created by hand in Cloudflare; adopt them instead of adding
# duplicates (two A records for one name would round-robin to the old server).
# Safe to delete these blocks once the import has been applied.
import {
  to = cloudflare_dns_record.teleport["teleport"]
  id = "${local.cloudflare["zone_id"]}/df471d3593e70876a4f8805d3a70802b"
}

import {
  to = cloudflare_dns_record.teleport["teleport_wildcard"]
  id = "${local.cloudflare["zone_id"]}/32aad1681f2f00d7e563ebf148184471"
}

# kids-app, migrated from the old cluster (ingress 192.168.0.202) to the
# proxmox-homelab cluster. .30 is that cluster's ingress-nginx LoadBalancer IP
# (first address of the MetalLB pool in k8s-addons).
resource "cloudflare_dns_record" "study" {
  zone_id = local.cloudflare["zone_id"]
  name    = "study.homebytes.space"
  type    = "A"
  content = "192.168.0.30"
  ttl     = 300
  proxied = false
}

import {
  to = cloudflare_dns_record.study
  id = "${local.cloudflare["zone_id"]}/415363529cc0466b0751ba541811428f"
}

# ase-market, migrated from the old cluster (ingress 192.168.0.202) to the
# proxmox-homelab cluster's ingress-nginx (.30), like kids-app above.
resource "cloudflare_dns_record" "ase_market" {
  zone_id = local.cloudflare["zone_id"]
  name    = "ase-market.homebytes.space"
  type    = "A"
  content = "192.168.0.30"
  ttl     = 300
  proxied = false
}

import {
  to = cloudflare_dns_record.ase_market
  id = "${local.cloudflare["zone_id"]}/6d1c867411df97f720a82db164da52b1"
}
