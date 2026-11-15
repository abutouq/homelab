# Ansible Playbooks

VMs, Vault, Teleport, cert-manager, Calico, node-exporter and Teleport apps
are built by [../packer/](../packer/) and [../terraform/](../terraform/)
(cloud-init + `terraform/k8s-addons/`). Ansible only does the kubeadm part:
turning the Terraform-built VMs into a cluster.

Run from this directory (an `ansible.cfg` here sets
`proxmox-k8s-cluster-hosts.ini` as the default inventory): `ansible-playbook <playbook>`

Or from the repo root: `ansible-playbook -i ansible/proxmox-k8s-cluster-hosts.ini ansible/<playbook>`

## Cluster bootstrap
Run in order, after `terraform apply` (see [../terraform/README.md](../terraform/README.md)):
1. `k8s_node_setup.yml` — base node setup: kernel modules, swap, sysctl, containerd, kubeadm/kubelet/kubectl install
2. `bootstrap_new_cluster.yml` — kube-vip VIP + `kubeadm init`/`join`, writes `~/.kube/config-new-cluster` (used by `terraform/k8s-addons/`)

## Proxmox hosts
The physical hosts can't be rebuilt from Terraform, so they're patched here:
- `proxmox_kernel_update.yml` — installs `kernel_version` and reboots hosts one at a time, waiting for quorum, the host's VMs and its Kubernetes nodes before moving on: `ansible-playbook -i proxmox-hosts.ini proxmox_kernel_update.yml`

## Inventory & configuration
- `proxmox-k8s-cluster-hosts.ini` — `control_plane` / `workers` groups (plus `new` for nodes pending setup)
- `proxmox-hosts.ini` — the 4 Proxmox hosts (`proxmox` group), in rolling-update order
- `ansible.cfg` — sets the default inventory path for this directory
- `group_vars/all.yml` — cluster-wide settings shared by playbooks (e.g. `kubernetes_version`)
