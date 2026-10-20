# openvpn image, cloned from the ubuntu-base template (9300). Build with: packer build -only='proxmox-clone.openvpn' .
# Baked in: openvpn + certbot packages and the static systemd/certbot glue.
# Left to cloud-init: openvpn.hcl (node_id, addresses), Cloudflare token, issuing the cert, starting openvpn.

source "proxmox-clone" "openvpn" {
  proxmox_url              = "https://192.168.0.201:8006/api2/json"
  username                 = "packer@pve!packer"
  token                    = local.proxmox_api_token_secret
  insecure_skip_tls_verify = true  # self-signed cert
  task_timeout             = "10m" # full clones of the 20G disk can exceed the 1m default when the node is busy
  node                     = "big"

  clone_vm_id          = 9300
  vm_id                = 9304
  vm_name              = "ubuntu-2404-openvpn-template"
  template_description = "openvpn on Ubuntu 24.04 built by Packer on ${timestamp()}"
  full_clone           = true
  cores                = 1
  memory               = 1024
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
  sources = ["source.proxmox-clone.openvpn"]

  # openvpn runs as the unprivileged openvpn user, so binding 443 needs CAP_NET_BIND_SERVICE on top of the package unit's CAP_IPC_LOCK.
  provisioner "file" {
    destination = "/tmp/bind-443.conf"
    content     = <<-EOF
      [Service]
      CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK CAP_NET_BIND_SERVICE
      AmbientCapabilities=CAP_IPC_LOCK CAP_NET_BIND_SERVICE
    EOF
  }

  # openvpn can't read /etc/letsencrypt/live, so each issuance/renewal copies the cert into openvpn's own dir and SIGHUPs openvpn (reloads listener certs without resealing).
  # certbot sets RENEWED_LINEAGE on renewals; for the first issuance, cloud-init runs this with RENEWED_LINEAGE=/etc/letsencrypt/live/<domain>.
  provisioner "file" {
    destination = "/tmp/openvpn-deploy-hook.sh"
    content     = <<-EOF
      #!/bin/bash
      set -euo pipefail
      install -o openvpn -g openvpn -m 0644 "$RENEWED_LINEAGE/fullchain.pem" /opt/openvpn/tls/fullchain.pem
      install -o openvpn -g openvpn -m 0600 "$RENEWED_LINEAGE/privkey.pem"   /opt/openvpn/tls/privkey.pem
      systemctl kill -s HUP openvpn.service || true
    EOF
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 1; done",
      "apt update && apt install -y openvpn easy-rsa",
      "mkdir -p /etc/openvpn/easy-rsa/pki && cd /etc/openvpn/easy-rsa",
      "make init-pki && make build-ca && make server && make client",
      "cat /etc/openvpn/easy-rsa/pki/ca.crt /etc/openvpn/easy-rsa/pki/issued/server.crt /etc/openvpn/easy-rsa/pki/private/server.key > /etc/openvpn/server.pem",
      "cat > /etc/openvpn/server.conf <<EOF",
      "port 1194",
      "proto udp",
      "dev tun0",
      "ca /etc/openvpn/easy-rsa/pki/ca.crt",
      "cert /etc/openvpn/easy-rsa/pki/issued/server.crt",
      "key /etc/openvpn/easy-rsa/pki/private/server.key",
      "server 10.8.0.0 255.255.255.0",
      "push \"route 192.168.1.0 255.255.255.0\"",
      "keepalive 10 60",
      "cipher AES-256-GCM",
      "user nobody",
      "group nogroup",
      "persist-key",
      "persist-tun",
      "status /var/log/openvpn-status.log",
      "verb 3",
      "EOF",
      "systemctl enable openvpn@server",
      "ip link set dev eth0 up",
      "sysctl -w net.ipv4.ip_forward=1",
      "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.d/99-openvpn.conf",
      "cloud-init clean --machine-id --seed",
      "rm -f /etc/ssh/ssh_host_* /var/lib/systemd/random-seed"
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
