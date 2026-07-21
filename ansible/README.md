# Ansible Playbooks

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
- `install_calico.yml` — one-time migration: remove leftover Flannel CNI state and finalize the Calico operator install (CNI is now Calico)

## Maintenance / troubleshooting
- `reset_cni_and_iscsi.yml` — reset CNI state and ensure iSCSI is installed
- `fix_kubelet_dns.yml` — fix kubelet DNS resolution via systemd-resolved
- `check_longhorn_preflight.yml` — run Longhorn CLI preflight checks
- `install_longhornctl.yml` — install the `longhornctl` binary

## Observability & access
- `install_node_exporter.yml` — install and run Prometheus Node Exporter
- `install_teleport.yml` — deploy the Teleport Kubernetes agent (Helm)

## External (standalone) hosts
Not part of the k8s cluster — see [../external-services/README.md](../external-services/README.md)
for the full walkthrough. These use a separate inventory (`ansible.cfg`
only defaults to `hosts.ini`), so pass `-i external-hosts.ini` explicitly,
and they prompt for sudo per run (`--ask-become-pass`) rather than storing
a password.
- `deploy_external_service.yml` — copy a `docker-compose.yml` from
  `external-services/<service>/` to a standalone host and `docker compose up -d`
- `manage_teleport_app.yml` — idempotently add/update/remove a
  `app_service` entry on the self-hosted Teleport control plane
  (`external-services/teleport/teleport.yaml`), restarting `teleport.service`
  only if it actually changed
- `files/manage_teleport_app.py` — the YAML-editing script the playbook above runs

## Inventory & configuration
- `hosts.ini` — `masters` / `workers` groups, with `homelab` (all nodes) and
  an empty `new` group for nodes pending cluster join
- `external-hosts.ini` — standalone hosts (outside the k8s cluster), currently just `192.168.0.158`
- `ansible.cfg` — sets the default inventory path for this directory
- `group_vars/all.yml` — cluster-wide settings shared by playbooks (e.g. `kubernetes_version`)
