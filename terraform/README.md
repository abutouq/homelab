# Terraform

Two independent Terraform root modules, run in sequence with Ansible steps in between — this isn't one `terraform apply` end to end, see [Order of operations](#order-of-operations-across-the-whole-toolchain).

- **`terraform/`** (this directory) — provisions Proxmox VMs for a second, standalone HA Kubernetes cluster (control-plane + worker nodes), separate from the existing cluster in `../ansible/`.
- **`terraform/k8s-addons/`** — installs cluster addons (CNI, MetalLB, ingress, cert-manager, metrics-server, ArgoCD) into that cluster once it exists. Own provider config, own state.

## Prerequisites

- Proxmox cluster `prx-cluster-01`: node `pve` (192.168.0.2), node `pve-02` (192.168.0.200).
- A least-privilege Proxmox API token for Terraform: user `terraform@pve`, role `TerraformProv` (VM lifecycle + datastore privileges), ACL granted at `/`. Never use `root@pam`'s own credentials here.
- **Cloud-init Ubuntu 24.04 templates, built manually — NOT Terraform-managed.** VMID `9000` on `pve`, VMID `9100` on `pve-02`. Terraform only clones these; it never creates them. See [Gotchas](#gotchas-learned-the-hard-way) — these have been accidentally deleted once already, which breaks every `module` block until rebuilt.

## `terraform/` — VM provisioning

`provider.tf` configures the `bpg/proxmox` provider. Credentials come from `variables.tf` (`PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN`) supplied via a gitignored `terraform.tfvars` or environment variables — never hardcoded in a `.tf` file.

`main.tf` has one `module` block per VM, all using `./modules/vm`:

| Module | vm_name | vm_id | Proxmox node | Template | IP |
|---|---|---|---|---|---|
| `tf_control_plane_01` | tf-control-plane-01 | 9001 | pve | 9000 | 192.168.0.3/24 |
| `tf_control_plane_02` | tf-control-plane-02 | 9002 | pve-02 | 9100 | 192.168.0.4/24 |
| `tf_worker_01` | tf-worker-01 | 9003 | pve | 9000 | 192.168.0.10/24 |
| `tf_worker_02` | tf-worker-02 | 9004 | pve-02 | 9100 | 192.168.0.11/24 |

`192.168.0.19` is reserved for the kube-vip control-plane VIP — it's not a VM and isn't Terraform-managed, it's assigned by `ansible/bootstrap_new_cluster.yml`.

### `modules/vm/`

A reusable "clone a VM from a template" module.

- **Inputs:** `vm_name`, `vm_id`, `node_name`, `template_vm_id`, `ip_address`, `gateway`, `ssh_public_key`.
- **Outputs:** `ip_address`, `vm_id`.
- **Behavior:** full clone (`clone.full = true`) of `template_vm_id` onto `node_name`, with cloud-init setting a key-only `ubuntu` user (no password — SSH key auth only) and a static IPv4 address.
- **Known limitation:** no `cpu_cores`/`memory_mb`/`disk_size` override — every clone inherits the template's fixed sizing exactly (currently 2 vCPU / 2GB RAM / 20.5GB disk, after the resize in [Gotchas](#gotchas-learned-the-hard-way)). If you need a bigger/smaller VM, resize after cloning via `qm resize`, or extend the module.

### Running it

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## `terraform/k8s-addons/` — cluster addons

A **separate** root module — only applicable *after* the cluster exists. `provider.tf` configures three providers (`helm`, `kubernetes`, `gavinbunney/kubectl`), all pointed at `var.kubeconfig_path` (default `~/.kube/config-new-cluster`), which is produced by `ansible/bootstrap_new_cluster.yml` — running `terraform apply` here before that playbook succeeds will fail outright (no kubeconfig to read).

`variables.tf`:
- `kubeconfig_path` — default `~/.kube/config-new-cluster`.
- `pod_cidr` — default `10.100.0.0/16`. **Must exactly match** the `--pod-network-cidr` passed to `kubeadm init` in `ansible/bootstrap_new_cluster.yml`.
- `metallb_pool` — default `192.168.0.30-192.168.0.69`. Must not overlap the *existing* cluster's MetalLB pool (`192.168.0.200-250`, see `../k8s-services/metallb-config.yaml`) — same flat LAN, two independent clusters.

Addons, in the order they actually get applied (via `depends_on`, since `helm_release` waits for pod rollout by default and nothing schedules without CNI):

1. **`calico.tf`** — Tigera operator chart, `ipPools[0].cidr = var.pod_cidr`. Everything else depends on this.
2. **`metallb.tf`** — MetalLB chart + an `IPAddressPool` (`var.metallb_pool`) + `L2Advertisement`, applied as raw CRs via the `kubectl` provider (`kubernetes_manifest` can't validate a CRD's schema in the same apply that creates the CRD; `kubectl_manifest` skips that problem).
3. **`ingress-nginx.tf`** — depends on MetalLB's `L2Advertisement`; `LoadBalancer` type, auto-assigned the first free pool IP (currently `192.168.0.30`).
4. **`cert-manager.tf`** — controller + CRDs only. No `ClusterIssuer` yet — a deliberate follow-up once this base install is confirmed working, not an oversight.
5. **`metrics-server.tf`** — `--kubelet-insecure-tls`, since kubelet's serving certs here are kubeadm's self-signed ones.
6. **`argocd.tf`** — `kubernetes_namespace` + `helm_release`, exposed via a **pinned** MetalLB IP (`192.168.0.31`, via the `metallb.io/loadBalancerIPs` annotation — `.30` was already claimed by ingress-nginx) rather than an `Ingress`. Proxied through the existing homelab's Teleport `app_service` (`../ansible/teleport_apps.yml`) instead of exposed directly on the LAN; `--insecure` because TLS terminates at Teleport's proxy, not here. `values.yaml` supplies replica counts, HPA settings, and the `global.domain`.

### Running it

```bash
cd terraform/k8s-addons
terraform init
terraform plan
terraform apply
```

## Order of operations across the whole toolchain

1. `terraform/` → `apply` — VMs exist.
2. `../ansible/k8s_node_setup.yml` → OS/package prep on all 4 VMs.
3. `../ansible/bootstrap_new_cluster.yml` → kube-vip + `kubeadm init`/`join`, produces `~/.kube/config-new-cluster`.
4. `terraform/k8s-addons/` → `apply` — CNI + addons, including ArgoCD.
5. `../ansible/manage_teleport_app.yml` → registers ArgoCD (and anything else added to `teleport_apps.yml`) for external access.

## Gotchas learned the hard way

- **Cloud-init only applies network config on a VM's first boot.** Changing `ip_address` in Terraform and running `apply` alone does *not* update a running VM's actual IP — Proxmox's cloud-init drive gets rewritten, but the guest OS won't re-read it without a reboot (`qm reboot <vmid>`).
- **Templates 9000/9100 are not Terraform resources.** They were built manually via `qm create`/`importdisk`/`template` and have been accidentally deleted once already, which broke every `module` block at once (`unable to find configuration file for VM <id> on node ...`). If that happens again, rebuild the template with `qm` before Terraform can do anything.
- **The template's original disk (3.5GB) was too small for a Kubernetes node** — `apt-get install kubelet kubeadm kubectl` ran out of space mid-install. Both templates and all 4 existing clones were resized to 20.5GB (`qm resize <vmid> scsi0 +17G`, then a reboot so cloud-init's `growpart`/`resizefs` picked it up).
- **Helm provider v3 changed syntax** from v2: `set { name = ... value = ... }` blocks became a `set = [{ name = ..., value = ... }]` list attribute, and `provider "helm" { kubernetes { ... } }` became `kubernetes = { ... }`. Code written against v2 docs fails `terraform validate` under the `~> 3.0` pin used here.
- **MetalLB hands out pool IPs automatically** for a plain `type: LoadBalancer` unless pinned. Pin (via `metallb.io/loadBalancerIPs`) any address something else will reference by a fixed value — e.g. a Teleport `app_service` URI — or a later auto-assigned service can silently claim it first. (This happened: ingress-nginx auto-claimed `.30` before ArgoCD tried to pin that same address.)
- **A `helm_release` that times out mid-install** ("context deadline exceeded") leaves Terraform's state without the resource, but Helm itself still has a `failed` release record blocking a plain reinstall ("cannot re-use a name that is still in use"). Fix with `terraform import helm_release.<name> <namespace>/<name>` so the next `apply` does an upgrade instead of a blocked install — don't `helm uninstall` working pods just to clear the error.

## Secrets & state

Gitignored (see `../.gitignore`): `terraform/**/.terraform/`, `**/*.tfstate*`, `**/*.tfvars`, `**/crash.log`. State files can contain sensitive values (e.g. resource attributes echoing back inputs); `.tfvars` holds the Proxmox API token. Never commit any of these.
