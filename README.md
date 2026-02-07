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

> ansible-playbook -i inventory.ini ansible/k8s-node-setup.yaml

* How/where to download your program
* Any modifications needed to be made to files/folders

<li>Open-iSCSI Installation</li>
Installs Open-iSCSI, which is required for Kubernetes persistent storage and Longhorn.

> ansible-playbook -i inventory.ini ansible/open-iscsi.yaml


<li>NFSv4 Setup</li>
Installs and configures NFSv4 support on all Kubernetes nodes.

> ansible-playbook -i inventory.ini ansible/NFSv4.yaml

<li>Cryptsetup Installation</li>

Installs cryptsetup for encrypted block device support (required by Longhorn).

> ansible-playbook -i inventory.ini ansible/cryptsetup.yaml

<li>Flannel Network Plugin</li>
Deploys the Flannel CNI for pod networking.

> ansible-playbook -i inventory.ini ansible/install_flannel.yaml

* If CNI logic is separated:
> ansible-playbook -i inventory.ini ansible/install_flannel_cni.yaml

<li>Install longhornctl</li>
Installs the Longhorn CLI (longhornctl) on the nodes or control host.

> ansible-playbook -i inventory.ini ansible/install_longhornctl.yaml

<li>Longhorn Preflight Checks</li>

Runs Longhorn preflight validation to ensure all nodes meet the requirements.

> ansible-playbook -i inventory.ini ansible/longhornctl_preflight.yaml
</ol>

## What This Cluster Runs
- NGINX Ingress Controller
- Longhorn for persistent storage
- Grafana + Prometheus

## Failure Scenarios
- Failure Scenario – Broken Ingress

    I intentionally misconfigured the Ingress to point to a non-existing Service.
    NGINX returned 503 Service Temporarily Unavailable, and kubectl describe ingress clearly showed that the backend Service was not found.
    This confirmed that Ingress routing, TLS, and the controller itself were working correctly, and the issue was isolated to the Service layer.

## Future Failure Scenarios Roadmap
- Node shutdown and pod rescheduling
- Broken deployment rollout and rollback
- PVC reattachment after pod deletion

## Key Design Decisions
- Why Flannel
- Why Longhorn
- Why Ingress instead of LoadBalancer
The LoadBalancer Service operates at Layer 4 (TCP/UDP), while the Ingress Controller works at Layer 7. By using NGINX Ingress, we can support host-based and path-based routing, as well as TLS termination