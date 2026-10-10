# Vault image, cloned from the ubuntu-base template (9300). Build with: packer build -only='proxmox-clone.vault' .
# Baked in: Vault + certbot packages and the static systemd/certbot glue.
# Left to cloud-init: vault.hcl (node_id, addresses), Cloudflare token, issuing the cert, starting Vault.

source "proxmox-clone" "vault" {
  proxmox_url              = "https://192.168.0.201:8006/api2/json"
  username                 = "packer@pve!packer"
  token                    = local.proxmox_api_token_secret
  insecure_skip_tls_verify = true  # self-signed cert
  task_timeout             = "10m" # full clones of the 20G disk can exceed the 1m default when the node is busy
  node                     = "external-services"

  clone_vm_id          = 9300
  vm_id                = 9301
  vm_name              = "ubuntu-2404-vault-template"
  template_description = "Vault on Ubuntu 24.04 built by Packer on ${timestamp()}"
  full_clone           = true
  cores                = 2
  memory               = 2048
  qemu_agent           = true

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  ipconfig {
    ip = "dhcp"
  }

  # Keep the cloud-init drive Terraform's initialization block needs (the clone builder drops it otherwise).
  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"

  ssh_username         = "ubuntu"
  ssh_private_key_file = "~/.ssh/id_ed25519"
  ssh_timeout          = "10m"
}

build {
  sources = ["source.proxmox-clone.vault"]

  # Vault runs as the unprivileged vault user, so binding 443 needs CAP_NET_BIND_SERVICE on top of the package unit's CAP_IPC_LOCK.
  provisioner "file" {
    destination = "/tmp/bind-443.conf"
    content     = <<-EOF
      [Service]
      CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK CAP_NET_BIND_SERVICE
      AmbientCapabilities=CAP_IPC_LOCK CAP_NET_BIND_SERVICE
    EOF
  }

  # Vault can't read /etc/letsencrypt/live, so each issuance/renewal copies the cert into Vault's own dir and SIGHUPs Vault (reloads listener certs without resealing).
  # certbot sets RENEWED_LINEAGE on renewals; for the first issuance, cloud-init runs this with RENEWED_LINEAGE=/etc/letsencrypt/live/<domain>.
  provisioner "file" {
    destination = "/tmp/vault-deploy-hook.sh"
    content     = <<-EOF
      #!/bin/bash
      set -euo pipefail
      install -o vault -g vault -m 0644 "$RENEWED_LINEAGE/fullchain.pem" /opt/vault/tls/fullchain.pem
      install -o vault -g vault -m 0600 "$RENEWED_LINEAGE/privkey.pem"   /opt/vault/tls/privkey.pem
      systemctl kill -s HUP vault.service || true
    EOF
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      # The clone's first boot runs cloud-init (and apt); wait so we don't race it for the apt lock.
      "cloud-init status --wait || [ $? -eq 2 ]",
      "curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg",
      "echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main\" | sudo tee /etc/apt/sources.list.d/hashicorp.list",
      "sudo apt-get update -qq",
      "sudo -E apt-get install -y vault certbot python3-certbot-dns-cloudflare",
      "sudo install -d -o vault -g vault -m 0750 /opt/vault/data /opt/vault/tls",
      "sudo install -D -m 0644 /tmp/bind-443.conf /etc/systemd/system/vault.service.d/bind-443.conf",
      "sudo install -D -m 0755 /tmp/vault-deploy-hook.sh /etc/letsencrypt/renewal-hooks/deploy/vault.sh",
      # Config and certs arrive per node via cloud-init; don't let a clone start Vault with the package defaults.
      "sudo systemctl disable vault",
      "vault version",
      "sudo rm -f /tmp/bind-443.conf /tmp/vault-deploy-hook.sh"
    ]
  }

  # Same reset as the base image, so clones get a fresh machine-id and run cloud-init again.
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo cloud-init clean --logs --machine-id",
      "sync"
    ]
  }
}
