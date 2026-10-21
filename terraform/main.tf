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

# Grafana admin on tf-grafana-01, published to Vault so you can look it up:
#   vault kv get secret/apps/grafana
resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "grafana_admin" {
  mount = "secret"
  name  = "apps/grafana"
  data_json = jsonencode({
    url            = "http://192.168.0.23:3000"
    admin_user     = "admin"
    admin_password = random_password.grafana_admin.result
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

# Read-only K8s identity for Prometheus on tf-grafana-01, written to Vault by
# k8s-addons/monitoring.tf. Read only if it exists: on a from-scratch build the
# cluster doesn't exist yet, so the VM comes up without cluster scrape jobs and
# the next apply (after k8s-addons) adds them.
data "vault_kv_secrets_list_v2" "homelab" {
  mount = "secret"
  name  = "homelab"
}

# Data sources rather than ephemeral: rendered into cloud-init (see provider.tf).
data "vault_generic_secret" "prometheus_k8s" {
  count = contains(nonsensitive(data.vault_kv_secrets_list_v2.homelab.names), "prometheus-k8s") ? 1 : 0
  path  = "secret/homelab/prometheus-k8s"
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
  # Grafana + Prometheus + Loki on one VM (was 2 GB for Grafana alone).
  memory_mb              = 3072
  grafana_admin_password = random_password.grafana_admin.result
  # Every *.json under grafana-dashboards/ (subdirectory = Grafana folder).
  grafana_dashboards = {
    for f in fileset("${path.root}/grafana-dashboards", "**/*.json") :
    f => filebase64("${path.root}/grafana-dashboards/${f}")
  }
  prometheus_k8s = length(data.vault_generic_secret.prometheus_k8s) == 0 ? null : {
    api_server = data.vault_generic_secret.prometheus_k8s[0].data["api_server"]
    token      = data.vault_generic_secret.prometheus_k8s[0].data["token"]
    ca_crt     = data.vault_generic_secret.prometheus_k8s[0].data["ca_crt"]
  }
  # node-exporter on the Proxmox hosts themselves (installed by bootstrap/)
  prometheus_node_targets   = ["192.168.0.2:9100", "192.168.0.200:9100", "192.168.0.201:9100", "192.168.0.202:9100"]
  prometheus_pihole_targets = ["${split("/", module.tf_pihole_01.ip_address)[0]}:9617"]
}


# OpenVPN PKI, owned by Terraform (in state, and the client profiles in Vault) rather
# than built on the VM, so rebuilding tf-openvpn-01 keeps the CA and every client keeps working.
# Add a device: append it to openvpn.clients and apply, then
#   vault kv get -field=<name> secret/apps/openvpn-clients > <name>.ovpn
#   vault kv get -field=<name>-totp secret/apps/openvpn-clients | qrencode -t ansiutf8
# and scan the QR code into an authenticator app. Connecting asks for a username
# (the client's name) and password (the app's current 6-digit code).
# Revoke one: remove it from the list and apply -replace=tls_self_signed_cert.openvpn_ca
# (there's no CRL, so that reissues every profile).
locals {
  openvpn = {
    # Resolves to the (static) WAN address via cloudflare_dns_record.vpn; the router
    # port-forwards UDP 1194 -> 192.168.0.24 (not managed here).
    remote  = "vpn.homebytes.space"
    wan_ip  = "185.96.69.137"
    port    = 1194
    clients = ["laptop", "phone"]
  }
  openvpn_validity_hours = 87600 # 10 years

  # OpenVPN's static key format: 256 random bytes as 16 lines of hex.
  openvpn_tls_crypt_key = join("\n", concat(
    ["-----BEGIN OpenVPN Static key V1-----"],
    [for i in range(16) : substr(random_bytes.openvpn_tls_crypt.hex, i * 32, 32)],
    ["-----END OpenVPN Static key V1-----", ""],
  ))
}

resource "tls_private_key" "openvpn_ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "openvpn_ca" {
  private_key_pem       = tls_private_key.openvpn_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = local.openvpn_validity_hours
  allowed_uses          = ["cert_signing", "crl_signing"]
  subject {
    common_name = "homelab OpenVPN CA"
  }
}

resource "tls_private_key" "openvpn_server" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "openvpn_server" {
  private_key_pem = tls_private_key.openvpn_server.private_key_pem
  subject {
    common_name = "tf-openvpn-01" # clients pin it with verify-x509-name
  }
}

resource "tls_locally_signed_cert" "openvpn_server" {
  cert_request_pem      = tls_cert_request.openvpn_server.cert_request_pem
  ca_private_key_pem    = tls_private_key.openvpn_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.openvpn_ca.cert_pem
  validity_period_hours = local.openvpn_validity_hours
  # serverAuth is what the clients' remote-cert-tls server checks.
  allowed_uses = ["digital_signature", "key_agreement", "server_auth"]
}

resource "tls_private_key" "openvpn_client" {
  for_each    = toset(local.openvpn.clients)
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "openvpn_client" {
  for_each        = toset(local.openvpn.clients)
  private_key_pem = tls_private_key.openvpn_client[each.key].private_key_pem
  subject {
    common_name = each.key
  }
}

resource "tls_locally_signed_cert" "openvpn_client" {
  for_each              = toset(local.openvpn.clients)
  cert_request_pem      = tls_cert_request.openvpn_client[each.key].cert_request_pem
  ca_private_key_pem    = tls_private_key.openvpn_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.openvpn_ca.cert_pem
  validity_period_hours = local.openvpn_validity_hours
  allowed_uses          = ["digital_signature", "client_auth"]
}

resource "random_bytes" "openvpn_tls_crypt" {
  length = 256
}

# TOTP secrets for the second factor: 32 base32 characters (160 bits, the RFC 4226 size).
resource "random_password" "openvpn_totp" {
  for_each         = toset(local.openvpn.clients)
  length           = 32
  upper            = true
  lower            = false
  numeric          = false
  special          = true
  override_special = "234567" # with A-Z, exactly the base32 alphabet
}

# Per client: <name> is its inline .ovpn profile, <name>-totp the otpauth:// URI
# for its authenticator app (see the comment above locals.openvpn).
resource "vault_kv_secret_v2" "openvpn_clients" {
  mount = "secret"
  name  = "apps/openvpn-clients"
  data_json = jsonencode(merge({
    for name in local.openvpn.clients : name => templatefile("${path.root}/openvpn/client.ovpn.tftpl", {
      name          = name
      totp          = true
      remote        = local.openvpn.remote
      port          = local.openvpn.port
      server_name   = tls_cert_request.openvpn_server.subject[0].common_name
      ca_cert       = tls_self_signed_cert.openvpn_ca.cert_pem
      cert          = tls_locally_signed_cert.openvpn_client[name].cert_pem
      key           = tls_private_key.openvpn_client[name].private_key_pem
      tls_crypt_key = local.openvpn_tls_crypt_key
    })
    }, {
    for name in local.openvpn.clients : "${name}-totp" =>
    "otpauth://totp/homelab-vpn:${name}?secret=${random_password.openvpn_totp[name].result}&issuer=homelab-vpn"
  }))
}

# The only public-IP record in the zone: VPN clients connect from outside the LAN.
# Not proxied, since Cloudflare's proxy doesn't carry UDP.
resource "cloudflare_dns_record" "vpn" {
  zone_id = local.cloudflare["zone_id"]
  name    = local.openvpn.remote
  type    = "A"
  content = local.openvpn.wan_ip
  ttl     = 300
  proxied = false
}

# Replaces the OpenVPN server on the old box (192.168.0.158).
module "tf_openvpn_01" {
  source              = "${path.root}/modules/vm"
  vm_name             = "tf-openvpn-01"
  vm_id               = 9010
  node_name           = "external-services" # node .201, where the Packer template is
  template_vm_id      = 9304                # Packer: packer/openvpn.pkr.hcl
  image_baked         = true
  ip_address          = "192.168.0.24/24"
  gateway             = "192.168.0.1"
  ssh_public_key      = trimspace(file("~/.ssh/id_ed25519.pub"))
  teleport_role       = "agent"
  teleport_join_token = random_password.teleport_join_token.result
  # teleport.homebytes.space still resolves to .158; drop this after the DNS cutover.
  teleport_proxy_ip = split("/", module.tf_teleport_apps_01.ip_address)[0]
  cpu_type          = "x86-64-v2-AES"
  cpu_cores         = 1
  memory_mb         = 1024
  openvpn_role      = "server"
  openvpn = {
    port        = local.openvpn.port
    push_routes = ["192.168.0.0/24"]
    # Clients resolve through Pi-hole (reachable: their traffic is NATed to this VM's LAN address).
    dns_servers   = [split("/", module.tf_pihole_01.ip_address)[0]]
    ca_cert       = tls_self_signed_cert.openvpn_ca.cert_pem
    server_cert   = tls_locally_signed_cert.openvpn_server.cert_pem
    server_key    = tls_private_key.openvpn_server.private_key_pem
    tls_crypt_key = local.openvpn_tls_crypt_key
    totp_secrets  = { for name, p in random_password.openvpn_totp : name => p.result }
  }
}

# Pi-hole, the LAN's DNS. Keeps the old server's address (192.168.0.158), which
# the router hands out over DHCP, so no client changes.
# Web UI password: vault kv get secret/apps/pihole
resource "random_password" "pihole_admin" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "pihole_admin" {
  mount = "secret"
  name  = "apps/pihole"
  data_json = jsonencode({
    url            = "https://pihole.teleport.homebytes.space/admin/"
    admin_password = random_password.pihole_admin.result
  })
}

# Devices and their groups (LAN IPs and device names stay out of this public repo).
data "vault_generic_secret" "pihole_clients" {
  path = "secret/apps/pihole-clients"
}

locals {
  pihole_lists = yamldecode(file("${path.root}/pihole/lists.yaml"))
}

module "tf_pihole_01" {
  source              = "${path.root}/modules/vm"
  vm_name             = "tf-pihole-01"
  vm_id               = 9009
  node_name           = "pve" # node .2
  template_vm_id      = 9000
  ip_address          = "192.168.0.158/24"
  gateway             = "192.168.0.1"
  ssh_public_key      = trimspace(file("~/.ssh/id_ed25519.pub"))
  teleport_role       = "agent"
  teleport_join_token = random_password.teleport_join_token.result
  teleport_apps       = { pihole = "http://127.0.0.1:80" }
  # Tiny: Pi-hole needs little. The cpu block needs a type to set cores.
  cpu_type  = "x86-64-v2-AES"
  cpu_cores = 1
  memory_mb = 768
  # Never resolve through itself (it is the LAN's DNS, and may be the one being rebuilt).
  dns_servers           = ["1.1.1.1", "1.0.0.1"]
  pihole_role           = "server"
  pihole_admin_password = random_password.pihole_admin.result
  pihole = {
    image          = "pihole/pihole:2026.09.0"
    exporter_image = "ekofr/pihole-exporter:v1.2.0"
    timezone       = "Asia/Amman"
    upstreams      = ["1.1.1.1", "1.0.0.1"]
    web_headers = [
      "X-DNS-Prefetch-Control: off",
      "Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;",
      "X-Frame-Options: DENY",
      "X-XSS-Protection: 0",
      "X-Content-Type-Options: nosniff",
      "Referrer-Policy: strict-origin-when-cross-origin",
    ]
    groups  = local.pihole_lists.groups
    adlists = local.pihole_lists.adlists
    domains = local.pihole_lists.domains
    clients = jsondecode(data.vault_generic_secret.pihole_clients.data_json).clients
  }
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
