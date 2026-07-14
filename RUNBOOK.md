# Runbook

Operational procedures for the homelab cluster: bootstrap order, day-2
operations, backup/restore, and incident playbooks. For architecture and
stack overview, see [README.md](README.md).

## Cluster Bootstrap (Execution Order)

⚠️ Run in this order on a fresh node — each step depends on the previous one.
Commands run from the repo root using `ansible/hosts.ini`.

| # | Step | Command |
|---|---|---|
| 1 | Kubernetes node base setup (kernel modules, sysctl, containerd, kubeadm/kubelet/kubectl) | `ansible-playbook -i ansible/hosts.ini ansible/k8s_node_setup.yml` |
| 2 | Open-iSCSI install (required for Longhorn) | `ansible-playbook -i ansible/hosts.ini ansible/install_open_iscsi.yml` |
| 3 | NFSv4 support check | `ansible-playbook -i ansible/hosts.ini ansible/check_nfsv4_support.yml` |
| 4 | Cryptsetup install (Longhorn encrypted volumes) | `ansible-playbook -i ansible/hosts.ini ansible/install_cryptsetup.yml` |
| 5 | Install `longhornctl` | `ansible-playbook -i ansible/hosts.ini ansible/install_longhornctl.yml` |
| 6 | Longhorn preflight checks | `ansible-playbook -i ansible/hosts.ini ansible/check_longhorn_preflight.yml` |

See [ansible/README.md](ansible/README.md) for the full playbook inventory,
including cluster bootstrap (`install_calico.yml`), maintenance
(`reset_cni_and_iscsi.yml`, `fix_kubelet_dns.yml`), and observability/access
(`install_node_exporter.yml`, `install_teleport.yml`) playbooks.

## Day-2 Operations

| Task | Command |
|---|---|
| List nodes | `kubectl get nodes` |
| Watch pod status | `kubectl get pods -w` |
| Pod detail / events | `kubectl describe pod <pod>` |
| Exec into a pod | `kubectl exec -it <pod> -- <cmd>` |
| Force-delete a stuck pod | `kubectl delete pod <pod> --grace-period=0 --force` |
| Fix kubelet DNS resolution | `ansible-playbook -i ansible/hosts.ini ansible/fix_kubelet_dns.yml` |
| Reset CNI state + ensure iSCSI | `ansible-playbook -i ansible/hosts.ini ansible/reset_cni_and_iscsi.yml` |

## Backup & Restore (Longhorn / StatefulSet data)

### Recover a StatefulSet pod stuck after a node failure

1. Force-delete the stuck pod:
   `kubectl delete pod mysql-0 --grace-period=0 --force`
2. If the Longhorn volume is still shown as "Attached" to the dead node, detach it from the Longhorn dashboard
3. Watch the pod get recreated and reattach the volume:
   `kubectl get pods -w`

Result: the StatefulSet recreates the pod with the same name on a healthy
node, Longhorn reattaches the existing volume, and the application starts
without data loss.

### Verify data persistence after scale-down/scale-up

`kubectl exec -it mysql-0 -- mysql -u root -p -e "SELECT * FROM app_data.users;"`

- PVCs and Longhorn volumes are retained across scale-down by design
- Scaling back up reuses the existing volume and data

## Upgrade Paths

- Kubernetes version is pinned via `kubernetes_version` in `ansible/group_vars/all.yml` and consumed by `ansible/k8s_node_setup.yml` (apt repo track `pkgs.k8s.io`)
- _TODO: document Calico, Longhorn, and Istio upgrade procedures_

## Incident Playbooks

### Quick reference

| Scenario | Symptom | Root cause | Fix |
|---|---|---|---|
| Broken Ingress | `503 Service Temporarily Unavailable` | Ingress points to a non-existent Service | Point Ingress `backend` at a valid Service |
| Node failure / StatefulSet pod stuck | Pod stuck `Terminating`, no replacement scheduled | Kubernetes won't reschedule StatefulSet pods until the node recovers (data safety) | Force-delete pod + detach Longhorn volume — see [Backup & Restore](#backup--restore-longhorn--statefulset-data) |
| ArgoCD unreachable via Teleport | "Internal Server Error" (HTTPS) or DNS error in browser (HTTP) | Auto-discovered Teleport apps default to `insecure_skip_verify: false` and forward internal redirect URLs | Add a static `apps` entry to `teleport/values.yaml` — see below |
| "Control plane is down" (cluster-wide pod Pending/Terminating) | All nodes appear unreachable; pods stuck `Pending`/`Terminating` cluster-wide | Control-plane node's Calico host-endpoint iptables chain silently dropped new inbound connections (ARP resolved, but ICMP/TCP did not) | Reboot the control-plane node to clear the stuck iptables/Calico state — see below |

---

### Broken Ingress

**Objective:** Validate Ingress, TLS, and controller behavior when the backend Service doesn't exist.

**Steps:** Misconfigure the Ingress to point to a non-existing Service.

**Observed behavior:**
- NGINX returns `503 Service Temporarily Unavailable`
- `kubectl describe ingress` shows the backend Service was not found

**Key takeaway:** Ingress routing, TLS, and the controller itself were working
correctly — the issue was isolated to the Service layer.

---

### Node Shutdown and Pod Rescheduling

**Objective:** Validate how Kubernetes behaves when a node hosting a StatefulSet pod is abruptly shut down.

**Steps:**
1. Identify the node running the pod: `kubectl get pod mysql-0 -o wide`
2. Shut down the node without draining it (simulate a real crash): `sudo shutdown -h now`
3. Observe node and pod state:
   - `kubectl get nodes`
   - `kubectl get pod mysql-0 -o wide -w`

**Observed behavior:**
- Node transitions to `NotReady`
- Pod initially remains `Running`
- After the eviction timeout, the pod enters `Terminating`
- No new pod is created automatically

**Explanation:** StatefulSets preserve pod identity and prevent duplicate
pods with the same ordinal. Kubernetes waits for the node to recover before
rescheduling, to avoid data corruption.

**Key takeaway:** Node shutdown does not immediately trigger pod recreation
for StatefulSets. Manual intervention is required if the node is permanently
unavailable — see [Backup & Restore](#backup--restore-longhorn--statefulset-data).

---

### PVC Persistence With Existing MySQL Data

**Objective:** Verify that existing MySQL data on a Longhorn-backed PVC
persists across StatefulSet scale-down and scale-up. The database and data
were created **before** this test.

**Precondition:**
- MySQL StatefulSet is running
- Database `app_data` and table `users` already exist and contain data

**Validation:** `kubectl exec -it mysql-0 -- mysql -u root -p -e "SELECT * FROM app_data.users;"`

**Observed behavior:**
- Pod with the higher ordinal is deleted during scale-down
- Corresponding PVC and Longhorn volume remain
- The original pod continues running with data intact

**Key takeaway:** StatefulSet scale-down deletes pods but preserves PVCs by
design. Longhorn retains the volume to prevent accidental data loss; scaling
back up reuses the existing volume and data.

---

### Teleport App Access Broken for ArgoCD

**Objective:** Diagnose why ArgoCD was unreachable through Teleport app
access, with two distinct errors depending on which auto-discovered app was
used.

**Symptoms:**
- `argocd-server-https-argocd-kubernetes` → **"Internal Server Error"** in the Teleport UI
- `argocd-server-http-argocd-kubernetes` → **"DNS_PROBE_POSSIBLE"** in the browser (`argocd-server.argocd.svc.cluster.local's DNS address could not be found`)

**Diagnosis:**

1. Inspect auto-discovered app definitions:
   ```bash
   tctl get apps | grep -A 10 "argocd-server"
   ```
   Both apps were created by the discovery service with `insecure_skip_verify: false`.

2. Check the ArgoCD network policy:
   ```bash
   kubectl get networkpolicy argocd-server-network-policy -n argocd -o yaml
   ```
   `ingress: [{}]` allows all inbound traffic — not the cause.

3. Confirm the ArgoCD service name and port:
   ```bash
   kubectl get svc -n argocd
   ```
   `argocd-server` on ports 80/443 — the URIs in the auto-discovered apps were correct.

**Root causes (two separate bugs):**

- **HTTPS app → "Internal Server Error":** `insecure_skip_verify: false` is
  the default for apps created by Kubernetes auto-discovery. ArgoCD uses a
  self-signed TLS certificate, so the Teleport agent rejected the TLS
  handshake before the connection reached ArgoCD.
- **HTTP app → browser DNS error:** ArgoCD's port 80 issues a `301` redirect
  to `https://argocd-server.argocd.svc.cluster.local/`. Teleport forwarded
  the `Location` header verbatim to the browser, which then tried (and
  failed) to resolve the internal Kubernetes DNS name from outside the
  cluster.

**Why `tctl create --force` is not the fix:** the Kubernetes discovery
service syncs periodically and regenerates the app resource from the live
Service spec — any manual patch to `insecure_skip_verify` or `rewrite` is
overwritten on the next sync cycle.

**Fix — static app entry in Helm values:**

Add an `apps` entry to `teleport/values.yaml` and re-run Helm upgrade. Static
apps defined here are served by the agent directly
(`teleport.dev/origin: config-file`) and are never touched by discovery.

```yaml
apps:
  - name: argocd
    uri: https://argocd-server.argocd.svc.cluster.local:443
    insecure_skip_verify: true
    rewrite:
      redirect:
        - "argocd-server.argocd.svc.cluster.local"
```

```bash
helm upgrade teleport-kube-agent teleport/teleport-kube-agent \
  -n teleport \
  --reuse-values \
  -f teleport/values.yaml
```

**Verification:**

```bash
# Confirm app_server is registered with correct spec
tctl get app_servers | grep -A 20 "name: argocd$"

# Test HTTPS reachability from within the teleport namespace
kubectl run -n teleport curl-test --image=curlimages/curl:latest --restart=Never \
  -- curl -sk -o /dev/null -w "%{http_code}" https://argocd-server.argocd.svc.cluster.local/
# Expected: 200
kubectl delete pod -n teleport curl-test
```

**Key takeaway:** Teleport Kubernetes app auto-discovery always creates apps
with `insecure_skip_verify: false` and no rewrite rules. Any service using a
self-signed cert or that issues internal-hostname redirects requires a
static `apps` entry in the agent Helm values to override those defaults. The
static entry coexists with discovery — the broken auto-discovered apps remain
but are unused.

### "Control Plane Is Down" (Cluster-Wide Outage)

**Objective:** Diagnose a reported control-plane outage on `pi5`
(`192.168.0.157`) that manifested as the entire cluster appearing dead.

**Symptoms:**
- Old pods stuck `Terminating` for weeks; new pods stuck `Pending` with no
  eligible node
- `kubectl get nodes` (run locally on `pi5`) showed all worker nodes
  `NotReady`
- Pinging `pi5` from any other host on the LAN timed out

**Diagnosis:**

1. Confirmed the control plane itself was healthy — not actually down:
   ```bash
   curl -sk https://localhost:6443/healthz   # -> 200 ok
   sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide
   ```
   `kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager`
   static pods were all `Running` continuously — no crash-loop. (The
   kubelet log spam `"probe already exists for container"` for these pods
   is a cosmetic kubelet bug, not a symptom.)

2. Found all worker nodes `NotReady`, with `NodeStatusUnknown` /
   `"Kubelet stopped posting node status"` since a specific timestamp per
   node — `kubectl describe node <worker> | sed -n '/Conditions:/,/Addresses:/p'`.

3. Confirmed the break was network-level, not kubelet-level: pinging
   `pi5` from a worker (and vice versa) failed completely, while the same
   worker could ping the LAN gateway and **the other worker** with 0% loss.
   That ruled out router-wide AP/client isolation (workers could reach each
   other fine) and pointed at something specific to `pi5`'s own host.

4. On `pi5`: `ufw` was inactive and the top-level `iptables` `INPUT`/`OUTPUT`
   policies were `ACCEPT` — so it wasn't a conventional host firewall.
   `sudo iptables -L cali-INPUT -n -v` showed traffic being routed through
   Calico's `cali-from-host-endpoint` chain (host-endpoint policy
   enforcement). ARP resolved `pi5`'s MAC correctly from every host, but no
   IP traffic (ICMP or TCP) got through in either direction — consistent
   with Calico's host-endpoint iptables state getting stuck after ~9 days
   of uptime, dropping new connections while leaving already-established
   ones (like an existing SSH session) untouched.

**Root cause:** `pi5`'s Calico host-endpoint iptables chain stopped
accepting new inbound connections. Every worker could reach the gateway and
each other, but nothing could reach `pi5`, and `pi5` couldn't reach anything
either — explaining why the whole cluster looked dead even though the
control plane process itself was healthy the entire time.

**Fix:** Reboot `pi5`. This cleared the stuck iptables/Calico state; both
healthy workers rejoined as `Ready` within moments of the control plane
coming back.

**Verification:**
```bash
ping -c3 192.168.0.157                 # 0% loss from any node
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide
```

**Key takeaway:** When a control plane "goes down" but `kubectl` still
works *locally on the node itself*, suspect the node's own network/iptables
state before assuming a Kubernetes-level failure. Symmetric ping tests
between peers (worker↔worker vs. worker↔control-plane) quickly isolate
whether the problem is network-wide (e.g. AP isolation) or specific to one
host. A single node's Calico host-endpoint chain can silently wedge itself
after long uptime without any corresponding kubelet or containerd crash.

**Related, separate issue found during this investigation (not yet fixed):**
`worker-04` (`192.168.0.155`) has a chronic PCIe/WiFi hardware fault —
its `iwlwifi` card's PCIe link logs continuous `AER: Correctable` /
`BadTLP` errors (336k+ in 6 days) with `ASPM L1 Enabled` on both ends of
the link. This is independent of the incident above (it doesn't fully
explain the simultaneous outage, since `worker-03` shows no such errors)
but is a real, ongoing reliability risk for that node. Candidate fix:
add `pcie_aspm=off` to `GRUB_CMDLINE_LINUX` and reboot — see
[Roadmap / Backlog](#roadmap--backlog).

---

## Roadmap / Backlog

- Broken deployment rollout and rollback
- `worker-04` chronic PCIe/WiFi `AER` bus errors (`ASPM L1` suspected) —
  apply `pcie_aspm=off` kernel boot parameter and confirm errors stop; see
  ["Control Plane Is Down"](#control-plane-is-down-cluster-wide-outage) incident
