# Ansible Playbooks

VMs, Vault, Teleport, cert-manager, Calico, node-exporter and Teleport apps
are now built by [../packer/](../packer/) and [../terraform/](../terraform/)
(cloud-init + `terraform/k8s-addons/`); the playbooks that used to do that
have been removed. What's left is kubeadm bootstrap and old-cluster upkeep.

Run from this directory (an `ansible.cfg` here sets `hosts.ini` as the default
inventory): `ansible-playbook <playbook>`

Or from the repo root: `ansible-playbook -i ansible/hosts.ini ansible/<playbook>`

## Node prerequisites
- `install_open_iscsi.yml` — install `open-iscsi` (required by Longhorn)
- `install_cryptsetup.yml` — install `cryptsetup` (required by Longhorn encrypted volumes)
- `install_nfs_common.yml` — install `nfs-common`
- `check_nfsv4_support.yml` — check kernel NFSv4/4.1/4.2 support

## Cluster bootstrap
- `k8s_node_setup.yml` — base node setup: kernel modules, swap, sysctl, containerd, kubeadm/kubelet/kubectl install
- `bootstrap_new_cluster.yml` — kube-vip VIP + `kubeadm init`/`join` for the Terraform-built HA cluster (inventory: `proxmox-k8s-cluster-hosts.ini`)

## Maintenance / troubleshooting
- `reset_cni_and_iscsi.yml` — reset CNI state and ensure iSCSI is installed
- `fix_kubelet_dns.yml` — fix kubelet DNS resolution via systemd-resolved
- `check_longhorn_preflight.yml` — run Longhorn CLI preflight checks
- `install_longhornctl.yml` — install the `longhornctl` binary

## Cluster add-ons
- `install_argocd_image_updater.yml` — zero-touch bootstrap of
  argocd-image-updater: scoped ArgoCD account + RBAC, a fresh API token
  (pushed to LocalStack), the `argocd-image-updater-secret` /
  `homelab-repo-creds` Secrets it needs, and the
  `argocd-image-updater[-secret-sync]` Applications. Safe to re-run (e.g.
  after a cluster rebuild). Its only prerequisite is a GitHub PAT seeded into
  LocalStack once ever (not once per cluster) — see the playbook header and
  [../argocd-image-updater/](../argocd-image-updater/)

## External (standalone) hosts
Not part of the k8s cluster — see [../external-services/README.md](../external-services/README.md)
for the full walkthrough. These use a separate inventory (`ansible.cfg`
only defaults to `hosts.ini`), so pass `-i external-hosts.ini` explicitly,
and they prompt for sudo per run (`--ask-become-pass`) rather than storing
a password.
- `deploy_external_service.yml` — copy a `docker-compose.yml` from
  `external-services/<service>/` to a standalone host and `docker compose up -d`

## Inventory & configuration
- `hosts.ini` — `masters` / `workers` groups, with `homelab` (all nodes) and
  an empty `new` group for nodes pending cluster join
- `proxmox-k8s-cluster-hosts.ini` — the Terraform-built HA cluster (`control_plane` / `workers`)
- `external-hosts.ini` — standalone hosts (outside the k8s cluster), currently just `192.168.0.158`
- `ansible.cfg` — sets the default inventory path for this directory
- `group_vars/all.yml` — cluster-wide settings shared by playbooks (e.g. `kubernetes_version`)
