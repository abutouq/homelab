# Monitoring image (Grafana + Prometheus + Loki), cloned from the ubuntu-base
# template (9300). Build with: make grafana
# Baked in: Grafana OSS and Loki from Grafana's apt repo; Prometheus from the
# official release tarball (pinned, checksum-verified) with a systemd unit.
# All three are installed disabled. Left to cloud-init: their configs,
# datasources, dashboards, admin credentials, and starting them.

variable "prometheus_version" {
  type    = string
  default = "3.5.0" # LTS
}

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
      "sudo -E apt-get install -y grafana loki",
      # Config arrives per node via cloud-init; don't start anything with the package defaults.
      "sudo systemctl disable --now grafana-server loki",
      "grafana-server --version",
      "loki --version | head -1"
    ]
  }

  provisioner "file" {
    source      = "files/prometheus.service"
    destination = "/tmp/prometheus.service"
  }

  provisioner "shell" {
    environment_vars = ["PROM=${var.prometheus_version}"]
    inline = [
      "cd /tmp",
      "curl -fsSLO https://github.com/prometheus/prometheus/releases/download/v$PROM/prometheus-$PROM.linux-amd64.tar.gz",
      "curl -fsSL https://github.com/prometheus/prometheus/releases/download/v$PROM/sha256sums.txt | grep -F \" prometheus-$PROM.linux-amd64.tar.gz\" | sha256sum -c -",
      "tar xzf prometheus-$PROM.linux-amd64.tar.gz",
      "sudo install -m 0755 prometheus-$PROM.linux-amd64/prometheus prometheus-$PROM.linux-amd64/promtool /usr/local/bin/",
      "sudo useradd --system --no-create-home --shell /usr/sbin/nologin prometheus",
      "sudo install -d -o prometheus -g prometheus /etc/prometheus /var/lib/prometheus",
      "sudo install -m 0644 /tmp/prometheus.service /etc/systemd/system/prometheus.service",
      "sudo systemctl daemon-reload",
      "prometheus --version | head -1"
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
