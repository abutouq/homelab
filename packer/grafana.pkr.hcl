# Grafana image, cloned from the ubuntu-base template (9300). Build with: make grafana
# Baked in: the Grafana OSS package from the official apt repo.
# Left to cloud-init: grafana.ini overrides, datasources, admin credentials, starting Grafana.

source "proxmox-clone" "grafana" {
  proxmox_url              = "https://192.168.0.201:8006/api2/json"
  username                 = "packer@pve!packer"
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true  # self-signed cert
  task_timeout             = "10m" # full clones of the 20G disk can exceed the 1m default when the node is busy
  node                     = "external-services"

  clone_vm_id          = 9300
  vm_id                = 9303
  vm_name              = "ubuntu-2404-grafana-template"
  template_description = "Grafana on Ubuntu 24.04 built by Packer on ${timestamp()}"
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
  sources = ["source.proxmox-clone.grafana"]

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      # The clone's first boot runs cloud-init (and apt); wait so we don't race it for the apt lock.
      "cloud-init status --wait || [ $? -eq 2 ]",
      "sudo mkdir -p /etc/apt/keyrings",
      "curl -fsSL https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg",
      "echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' | sudo tee /etc/apt/sources.list.d/grafana.list",
      "sudo apt-get update -qq",
      "sudo -E apt-get install -y grafana",
      # Config arrives per node via cloud-init; don't start Grafana with the package defaults.
      "sudo systemctl disable grafana-server",
      "grafana-server --version"
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
