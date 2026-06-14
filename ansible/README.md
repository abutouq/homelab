# Ansible Playbooks

Run from this directory (an `ansible.cfg` here sets `hosts.ini` as the default
inventory): `ansible-playbook <playbook>`

Or from the repo root: `ansible-playbook -i ansible/hosts.ini ansible/<playbook>`

## Node prerequisites
- `install_open_iscsi.yml` — install `open-iscsi` (required by Longhorn)
- `install_cryptsetup.yml` — install `cryptsetup` (required by Longhorn encrypted volumes)
- `install_nfs_common.yaml` — install `nfs-common`
- `NFSv4.yaml` — check kernel NFSv4/4.1/4.2 support

## Cluster bootstrap
- `k8s-node-setup.yml` — base node setup: kernel modules, swap, sysctl, containerd, kubeadm/kubelet/kubectl install
- `install_calico.yaml` — one-time migration: remove leftover Flannel CNI state and finalize the Calico operator install (CNI is now Calico)

## Maintenance / troubleshooting
- `check.yaml` — reset CNI state and ensure iSCSI is installed
- `k8s_fix_kubelet_dns.yaml` — fix kubelet DNS resolution via systemd-resolved
- `longhornctl_preflight.yaml` — run Longhorn CLI preflight checks
- `install_longhornctl.yaml` — install the `longhornctl` binary

## Observability & access
- `node_exporter_install.yaml` — install and run Prometheus Node Exporter
- `install_teleport.yaml` — deploy the Teleport Kubernetes agent (Helm)

## Inventory & configuration
- `hosts.ini` — `masters` / `workers` groups, with `homelab` (all nodes) and
  an empty `new` group for nodes pending cluster join
- `ansible.cfg` — sets the default inventory path for this directory
- `group_vars/all.yml` — cluster-wide settings shared by playbooks (e.g. `kubernetes_version`)
