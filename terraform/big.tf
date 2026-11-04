# Immich and the NAS on big (192.168.0.202). Their data lives on "tank-vm", the
# ZFS mirror of big's two extra disks (SSD + HDD), set up by bootstrap/.
#
# Run order on a fresh build: bootstrap (creates the pool from the empty SSD),
# then this stack (seeds the Immich library from the HDD, builds the VMs), then
# flip big_mirror in bootstrap/ to add the HDD to the pool -- that last step
# wipes the HDD, so it's off until the copy has been checked in Immich.

# Same image as template 9000 on pve, as an "import" volume so the template can import it.
resource "proxmox_download_file" "noble_cloudimg_big" {
  content_type = "import"
  datastore_id = "local"
  node_name    = local.nodes.big.name
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "noble-server-cloudimg-amd64.qcow2"
  overwrite    = false # don't replace the template every time Ubuntu republishes "current"
}

# big's clone source. Templates sit on node-local storage, so each node needs its own.
resource "proxmox_virtual_environment_vm" "template_big" {
  name      = "ubuntu-2404-cloudinit-template"
  node_name = local.nodes.big.name
  vm_id     = local.nodes.big.template
  template  = true
  started   = false

  agent {
    enabled = true
  }
  cpu {
    cores = 2
  }
  memory {
    dedicated = 2048
  }
  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["scsi0"]

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    import_from  = proxmox_download_file.noble_cloudimg_big.id
    size         = 20
  }

  initialization {
    datastore_id = "local-lvm"
    interface    = "ide2"
  }

  network_device {
    bridge = "vmbr0"
  }
  serial_device {}
  vga {
    type = "serial0"
  }
  operating_system {
    type = "l26"
  }
}

# Never started: only owns the data volumes, which tf-immich-01 and tf-nas-01
# attach by path. Recreating either VM leaves its data here.
resource "proxmox_virtual_environment_vm" "data_big" {
  name      = "big-data-disks"
  node_name = local.nodes.big.name
  vm_id     = 9013
  started   = false
  on_boot   = false

  # Immich: library + Postgres. Quota-like cap; grow with qm disk resize + resize2fs.
  disk {
    datastore_id = local.nodes.big.datastore
    interface    = "scsi0"
    file_format  = "raw"
    size         = 300
  }
  # NAS share
  disk {
    datastore_id = local.nodes.big.datastore
    interface    = "scsi1"
    file_format  = "raw"
    size         = 100
  }

  lifecycle {
    prevent_destroy = true
  }
}

# One-time copy of the old Immich library (photos + Immich's DB dumps) from the
# HDD onto the Immich data volume, done on the host before the VM first boots.
# The HDD is mounted read-only. The checksum pass must find no differences, and
# only then is /root/.immich-seed-verified written: bootstrap/ won't wipe the
# HDD into the mirror without it.
resource "terraform_data" "immich_seed" {
  input = proxmox_virtual_environment_vm.data_big.disk[0].path_in_datastore

  connection {
    type        = "ssh"
    host        = local.nodes.big.host
    user        = "root"
    private_key = file("~/.ssh/id_ed25519")
  }

  provisioner "remote-exec" {
    inline = [<<-EOT
      set -eu
      vol=/dev/zvol/tank/vm/${self.input}
      udevadm settle
      [ -e "$vol" ]
      blkid "$vol" >/dev/null || mkfs.ext4 -q -L immich-data "$vol"
      mkdir -p /mnt/immich-data /mnt/old-library
      mount "$vol" /mnt/immich-data
      trap 'umount /mnt/old-library 2>/dev/null; umount /mnt/immich-data' EXIT
      if [ -e /mnt/immich-data/.seeded ]; then echo "already seeded"; exit 0; fi

      mount -o ro,noload ${local.nodes.big.old_library_disk} /mnt/old-library
      rsync -aHAX --info=progress2 /mnt/old-library/immich-library/ /mnt/immich-data/library/
      diffs=$(rsync -aHAXc --dry-run --itemize-changes /mnt/old-library/immich-library/ /mnt/immich-data/library/ | wc -l)
      if [ "$diffs" -ne 0 ]; then echo "checksum pass found $diffs differences" >&2; exit 1; fi
      touch /mnt/immich-data/.seeded /root/.immich-seed-verified
      echo "seeded and verified"
    EOT
    ]
  }
}

# Immich DB password, published to Vault: vault kv get secret/apps/immich
resource "random_password" "immich_db" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "immich" {
  mount = "secret"
  name  = "apps/immich"
  data_json = jsonencode({
    url         = "https://immich.teleport.homebytes.space"
    db_password = random_password.immich_db.result
  })
}

module "tf_immich_01" {
  source              = "${path.root}/modules/vm"
  depends_on          = [terraform_data.immich_seed]
  vm_name             = "tf-immich-01"
  vm_id               = 9011
  node_name           = local.nodes.big.name
  template_vm_id      = proxmox_virtual_environment_vm.template_big.vm_id
  ip_address          = "192.168.0.25/24"
  gateway             = "192.168.0.1"
  ssh_public_key      = trimspace(file("~/.ssh/id_ed25519.pub"))
  teleport_role       = "agent"
  teleport_join_token = random_password.teleport_join_token.result
  # teleport.homebytes.space still resolves to .158; drop this after the DNS cutover.
  teleport_proxy_ip = split("/", module.tf_teleport_apps_01.ip_address)[0]
  teleport_apps     = { immich = "http://localhost:2283" }
  # Immich's machine-learning image needs AVX; big has AVX2.
  cpu_type  = "x86-64-v3"
  cpu_cores = 2
  memory_mb = 6144
  data_disk = {
    datastore_id      = local.nodes.big.datastore
    path_in_datastore = proxmox_virtual_environment_vm.data_big.disk[0].path_in_datastore
    size              = proxmox_virtual_environment_vm.data_big.disk[0].size
  }
  immich_role = "server"
  immich = {
    compose = file("${path.root}/immich/docker-compose.yml")
    # The version that wrote the dumps being restored; upgrade after the restore.
    version     = "v3.1.0"
    db_password = random_password.immich_db.result
  }
}

# Samba password, published to Vault: vault kv get secret/apps/nas
resource "random_password" "nas" {
  length  = 24
  special = false
}

resource "vault_kv_secret_v2" "nas" {
  mount = "secret"
  name  = "apps/nas"
  data_json = jsonencode({
    url      = "smb://192.168.0.26/share"
    user     = "nas"
    password = random_password.nas.result
  })
}

module "tf_nas_01" {
  source              = "${path.root}/modules/vm"
  vm_name             = "tf-nas-01"
  vm_id               = 9012
  node_name           = local.nodes.big.name
  template_vm_id      = proxmox_virtual_environment_vm.template_big.vm_id
  ip_address          = "192.168.0.26/24"
  gateway             = "192.168.0.1"
  ssh_public_key      = trimspace(file("~/.ssh/id_ed25519.pub"))
  teleport_role       = "agent"
  teleport_join_token = random_password.teleport_join_token.result
  # teleport.homebytes.space still resolves to .158; drop this after the DNS cutover.
  teleport_proxy_ip = split("/", module.tf_teleport_apps_01.ip_address)[0]
  data_disk = {
    datastore_id      = local.nodes.big.datastore
    path_in_datastore = proxmox_virtual_environment_vm.data_big.disk[1].path_in_datastore
    size              = proxmox_virtual_environment_vm.data_big.disk[1].size
  }
  nas_role = "server"
  nas = {
    user        = "nas"
    password    = random_password.nas.result
    hosts_allow = ["192.168.0.0/24"]
    # NFS for the nas-nfs StorageClass (k8s-addons/nfs-csi.tf): the cluster's nodes only.
    nfs_clients = [for m in [module.tf_control_plane_01, module.tf_control_plane_02, module.tf_worker_01, module.tf_worker_02] : split("/", m.ip_address)[0]]
  }
}
