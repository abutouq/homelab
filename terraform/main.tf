module "tf_control_plane_01" {
  source         = "./modules/vm"
  vm_name        = "tf-control-plane-01"
  vm_id          = 9001
  node_name      = "pve"          # node .2
  template_vm_id = 9000
  ip_address     = "192.168.0.3/24"
  gateway        = "192.168.0.1"
  ssh_public_key = trimspace(file("~/.ssh/id_ed25519.pub"))
}

module "tf_control_plane_02" {
  source         = "./modules/vm"
  vm_name        = "tf-control-plane-02"
  vm_id          = 9002
  node_name      = "pve-02"        # node .200
  template_vm_id = 9100
  ip_address     = "192.168.0.4/24"
  gateway        = "192.168.0.1"
  ssh_public_key = trimspace(file("~/.ssh/id_ed25519.pub"))
}

module "tf_worker_01" {
  source         = "./modules/vm"
  vm_name        = "tf-worker-01"
  vm_id          = 9003
  node_name      = "pve"          # node .2
  template_vm_id = 9000
  ip_address     = "192.168.0.10/24"
  gateway        = "192.168.0.1"
  ssh_public_key = trimspace(file("~/.ssh/id_ed25519.pub"))
}

module "tf_worker_02" {
  source         = "./modules/vm"
  vm_name        = "tf-worker-02"
  vm_id          = 9004
  node_name      = "pve-02"        # node .200
  template_vm_id = 9100
  ip_address     = "192.168.0.11/24"
  gateway        = "192.168.0.1"
  ssh_public_key = trimspace(file("~/.ssh/id_ed25519.pub"))
}

module "tf_external_services_01" {
  source         = "./modules/vm"
  vm_name        = "tf-external-services-01"
  vm_id          = 9005
  node_name      = "external-services" # node .201
  template_vm_id = 9200
  ip_address     = "192.168.0.20/24"
  gateway        = "192.168.0.1"
  ssh_public_key = trimspace(file("~/.ssh/id_ed25519.pub"))
}

module "tf_teleport_apps_01" {
  source         = "./modules/vm"
  vm_name        = "tf-teleport-apps-01"
  vm_id          = 9006
  node_name      = "external-services" # node .201
  template_vm_id = 9200
  ip_address     = "192.168.0.21/24"
  gateway        = "192.168.0.1"
  ssh_public_key = trimspace(file("~/.ssh/id_ed25519.pub"))
}

module "tf_vault_01" {
  source         = "./modules/vm"
  vm_name        = "tf-vault-01"
  vm_id          = 9007
  node_name      = "external-services" # node .201
  template_vm_id = 9200
  ip_address     = "192.168.0.22/24"
  gateway        = "192.168.0.1"
  ssh_public_key = trimspace(file("~/.ssh/id_ed25519.pub"))
}