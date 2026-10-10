# Teleport image, cloned from the ubuntu-base template (9300). Build with: make teleport
# Baked in: certbot with the Cloudflare plugin (the Teleport package itself comes from the base image).
# Left to cloud-init: /etc/teleport.yaml, join token, Cloudflare token, issuing the cert, starting Teleport.

source "proxmox-clone" "teleport" {
  proxmox_url              = "https://192.168.0.201:8006/api2/json"
  username                 = "packer@pve!packer"
  token                    = local.proxmox_api_token_secret
  insecure_skip_tls_verify = true  # self-signed cert
  task_timeout             = "10m" # full clones of the 20G disk can exceed the 1m default when the node is busy
  node                     = "external-services"

  clone_vm_id          = 9300
  vm_id                = 9302
  vm_name              = "ubuntu-2404-teleport-template"
  template_description = "Teleport on Ubuntu 24.04 built by Packer on ${timestamp()}"
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
  sources = ["source.proxmox-clone.teleport"]

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      # The clone's first boot runs cloud-init (and apt); wait so we don't race it for the apt lock.
      "cloud-init status --wait || [ $? -eq 2 ]",
      "sudo apt-get update -qq",
      "sudo -E apt-get install -y certbot python3-certbot-dns-cloudflare",
      "teleport version"
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
