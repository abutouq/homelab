# Kubernetes Homelab

This repository contains my Kubernetes homelab setup, where I document and share my learning journey

## Architecture

![Cluster Diagram](architecture/cluster-diagram.png)

## Getting Started

### Prerequisites
Before you begin, make sure you have:
<ol>
<li>Ansible installed on the control machine</li>
<li>SSH access to all target nodes</li>
<li>Inventory file properly configured (masters/workers)</li>
<li>Passwordless sudo on all nodes</li>
</ol>

Internet access from nodes (or a local mirror/registry)

### Execution Order (Important)
⚠️ The playbooks must be executed in the following order to avoid dependency issues.
<ol>
<li>Kubernetes Node Base Setup</li>

* Prepares all nodes with required kernel modules, sysctl settings, and base system packages.

> ansible-playbook -i ansible/hosts.ini ansible/k8s_node_setup.yml

<li>Open-iSCSI Installation</li>
Installs Open-iSCSI, which is required for Kubernetes persistent storage and Longhorn.

> ansible-playbook -i ansible/hosts.ini ansible/install_open_iscsi.yml


<li>NFSv4 Setup</li>
Installs and configures NFSv4 support on all Kubernetes nodes.

> ansible-playbook -i ansible/hosts.ini ansible/check_nfsv4_support.yml

<li>Cryptsetup Installation</li>

Installs cryptsetup for encrypted block device support (required by Longhorn).

> ansible-playbook -i ansible/hosts.ini ansible/install_cryptsetup.yml

<li>Install longhornctl</li>
Installs the Longhorn CLI (longhornctl) on the nodes or control host.

> ansible-playbook -i ansible/hosts.ini ansible/install_longhornctl.yml

<li>Longhorn Preflight Checks</li>

Runs Longhorn preflight validation to ensure all nodes meet the requirements.

> ansible-playbook -i ansible/hosts.ini ansible/check_longhorn_preflight.yml
</ol>

See [ansible/README.md](ansible/README.md) for the full playbook inventory
and configuration layout (`group_vars`, `host_vars`, `ansible.cfg`).

## What This Cluster Runs
- NGINX Ingress Controller
- Longhorn for persistent storage
- Grafana + Prometheus

## Failure Scenarios
### Scenario 1: Failure Scenario – Broken Ingress

I intentionally misconfigured the Ingress to point to a non-existing Service.
NGINX returned `503 Service Temporarily Unavailable`, and kubectl describe ingress clearly showed that the backend Service was not found.
This confirmed that Ingress routing, TLS, and the controller itself were working correctly, and the issue was isolated to the Service layer.

---

### Scenario 2: Node Shutdown and Pod Rescheduling

#### Objective
Validate how Kubernetes behaves when a node hosting a StatefulSet pod is abruptly
shut down.

#### Test Steps
1. Identify the node running the StatefulSet pod:
   `kubectl get pod mysql-0 -o wide`

2. Shut down the node without draining it (simulate a real crash):
   `sudo shutdown -h now`

3. Observe node and pod state:

   `kubectl get nodes`

   `kubectl get pod mysql-0 -o wide -w`

#### Observed Behavior
- Node transitions to `NotReady`
- Pod initially remains in Running state
- After the eviction timeout, the pod enters Terminating state
- No new pod is created automatically

#### Explanation
StatefulSets preserve pod identity and prevent duplicate pods with the same ordinal.
Kubernetes waits for the node to recover before rescheduling to avoid data corruption.

#### Key Takeaway
Node shutdown does not immediately trigger pod recreation for StatefulSets.
Manual intervention is required if the node is permanently unavailable.

---

### Scenario 3 Recovery: Manual Pod Rescheduling

#### Objective
Recover a StatefulSet pod when the node is permanently down.

#### Recovery Steps

1. Force delete the stuck pod:

   `kubectl delete pod mysql-0 --grace-period=0 --force`

2. Unattach the disk from Longhorn dashboard

3. Watch the pod get recreated:

   `kubectl get pods -w`

#### Result
- The StatefulSet recreates the pod with the same name
- The pod is scheduled on a healthy node
- Longhorn reattaches the existing volume
- The application starts successfully

#### Key Takeaway
When a node is permanently unavailable, force-deleting the pod allows Kubernetes
and Longhorn to safely reschedule the workload without data loss.

---

### Scenario 4: PVC Persistence With Existing MySQL Data

#### Objective
Verify that existing MySQL data stored on a Longhorn-backed PVC
persists across StatefulSet scale-down and scale-up operations.

The database and data were created **before** this test.

#### Precondition
- MySQL StatefulSet is running
- Database `app_data` already exists
- Table `users` already exists and contains data

#### Data Validation

Verify the original data is still present:

`kubectl exec -it mysql-0 -- mysql -u root -p -e "SELECT * FROM app_data.users;"`

#### Observed Behavior

- Pod with higher ordinal is deleted during scale-down
- Corresponding PVC and Longhorn volume remain
- Original pod continues running
- MySQL data remains intact and accessible

#### Key Takeaway

StatefulSet scale-down deletes pods but preserves PVCs by design.
Longhorn retains the volume to prevent accidental data loss.
Scaling back up will reuse the existing volume and data.


---

### Scenario 5: Teleport App Access Broken for ArgoCD

#### Objective
Diagnose why ArgoCD was unreachable through Teleport app access, presenting two
distinct errors depending on which auto-discovered app was used.

#### Symptoms
- `argocd-server-https-argocd-kubernetes` → **"Internal Server Error"** in the Teleport UI
- `argocd-server-http-argocd-kubernetes` → **"DNS_PROBE_POSSIBLE"** in the browser
  (`argocd-server.argocd.svc.cluster.local's DNS address could not be found`)

#### Diagnosis

**Step 1 — Inspect auto-discovered app definitions:**

```
tctl get apps | grep -A 10 "argocd-server"
```

Both apps were created by the discovery service with `insecure_skip_verify: false`.

**Step 2 — Check ArgoCD network policy:**

```
kubectl get networkpolicy argocd-server-network-policy -n argocd -o yaml
```

`ingress: [{}]` — allows all inbound traffic. Not the cause.

**Step 3 — Confirm ArgoCD service name and port:**

```
kubectl get svc -n argocd
```

`argocd-server` on ports 80/443. The URIs in the auto-discovered apps were correct.

#### Root Causes (two separate bugs)

**Bug 1 — HTTPS app → "Internal Server Error"**

`insecure_skip_verify: false` is the default for all apps created by Kubernetes auto-discovery.
ArgoCD uses a self-signed TLS certificate. The Teleport agent rejected the TLS handshake before
the connection reached ArgoCD.

**Bug 2 — HTTP app → browser DNS error**

ArgoCD's port 80 issues a `301` redirect to `https://argocd-server.argocd.svc.cluster.local/`.
Teleport forwarded the `Location` header verbatim to the browser. The browser then tried to
resolve the internal Kubernetes DNS name — impossible from outside the cluster.

#### Why `tctl create --force` is not the fix

The Kubernetes discovery service syncs periodically and re-generates the app resource from
the live Kubernetes service spec. Any manual patch to `insecure_skip_verify` or `rewrite` would
be overwritten on the next sync cycle.

#### Fix — Static app entry in Helm values

Add an `apps` entry to `teleport/values.yaml` and re-run Helm upgrade. Static apps defined here
are served by the agent directly (with `teleport.dev/origin: config-file`) and are never touched
by the discovery service.

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

#### Verification

```bash
# Confirm app_server is registered with correct spec
tctl get app_servers | grep -A 20 "name: argocd$"

# Test HTTPS reachability from within the teleport namespace
kubectl run -n teleport curl-test --image=curlimages/curl:latest --restart=Never \
  -- curl -sk -o /dev/null -w "%{http_code}" https://argocd-server.argocd.svc.cluster.local/
# Expected: 200
kubectl delete pod -n teleport curl-test
```

#### Key Takeaway

Teleport Kubernetes app auto-discovery always creates apps with `insecure_skip_verify: false`
and no rewrite rules. Any service using a self-signed cert or that issues internal-hostname
redirects requires a static `apps` entry in the agent Helm values to override those defaults.
The static entry coexists with discovery — the broken auto-discovered apps remain but are unused.

---

## Future Failure Scenarios Roadmap
- Broken deployment rollout and rollback

## Key Design Decisions
- Why Flannel
- Why Longhorn
- Why Ingress instead of LoadBalancer
The LoadBalancer Service operates at Layer 4 (TCP/UDP), while the Ingress Controller works at Layer 7. By using NGINX Ingress, we can support host-based and path-based routing, as well as TLS termination