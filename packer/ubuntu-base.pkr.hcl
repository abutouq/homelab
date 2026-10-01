packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.0"
    }
  }
}

# Only the token secret is a variable -- supply it via the gitignored secrets.auto.pkrvars.hcl.
variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}

source "proxmox-iso" "ubuntu" {
  # Proxmox API connection (packer@pve user, Packer role)
  proxmox_url              = "https://192.168.0.201:8006/api2/json"
  username                 = "packer@pve!packer"
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true # self-signed cert
  node                     = "external-services"

  # 9000 is the existing cloud-image template Terraform clones; 9300 is free.
  vm_id                = 9300
  vm_name              = "ubuntu-2404-packer-template"
  template_description = "Ubuntu 24.04 built by Packer on ${timestamp()}"
  cores                = 2
  memory               = 2048
  qemu_agent           = true

  scsi_controller = "virtio-scsi-pci"
  disks {
    disk_size    = "20G"
    storage_pool = "local-lvm"
    type         = "scsi"
  }

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Cloud-init drive, like template 9000, so Terraform's initialization block works on clones.
  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"

  # Packer downloads the ISO to Proxmox 'local' storage once and detaches it from the template.
  boot_iso {
    type     = "ide"
    iso_file = "local:iso/ubuntu-24.04.5-live-server-amd64.iso"
    unmount  = true
  }

  # Autoinstall config served from Packer's built-in HTTP server (no http/ directory needed).
  http_content = {
    "/meta-data" = ""
    "/user-data" = <<-EOF
      #cloud-config
      autoinstall:
        version: 1
        locale: en_US.UTF-8
        keyboard:
          layout: us
        storage:
          layout:
            name: direct
        identity:
          hostname: ubuntu-template
          username: ubuntu
          # Hash of a random throwaway password; login is SSH-key only.
          password: "$6$0Gl09dZpITwU4cUU$H64bf2jngafHeMn8q500IhBXdqVQpi2dzSuIbPUGe4vR7d7i4XJ35clnhmp15.Z0o6Mhv08WziLe/i5jbYJKY."
        ssh:
          install-server: true
          allow-pw: false
          authorized-keys:
            - ${trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))}
        packages:
          - qemu-guest-agent
        late-commands:
          - echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/ubuntu
          - curtin in-target -- systemctl enable qemu-guest-agent
    EOF
  }

  boot_wait = "5s"
  boot_command = [
    "<wait>c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/<enter><wait10>",
    "initrd /casper/initrd<enter><wait10>",
    "boot<enter>"
  ]

  ssh_username         = "ubuntu"
  ssh_private_key_file = "~/.ssh/id_ed25519"
  ssh_timeout          = "30m"
}

build {
  sources = ["source.proxmox-iso.ubuntu"]

  # Reset installer leftovers so clones run cloud-init fresh from the Proxmox cloud-init drive.
  provisioner "shell" {
    inline = [
      "sudo rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg /etc/cloud/cloud.cfg.d/90-installer-network.cfg /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg /etc/netplan/*.yaml",
      "echo 'datasource_list: [ConfigDrive, NoCloud]' | sudo tee /etc/cloud/cloud.cfg.d/99-pve.cfg",
      "sudo apt-get clean",
      "sudo cloud-init clean --logs --machine-id",
      "sync"
    ]
  }
}
