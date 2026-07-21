# Standalone Hosts

Services that run directly on a host, outside the Kubernetes cluster
documented in the root [README.md](../README.md) and provisioned by
[ansible/](../ansible/): Docker Compose stacks and the self-hosted
Teleport control plane. The config files here are the source of truth —
edit them in this repo, then copy/deploy to the host, rather than
editing in place on the server. That drift (manual `.bak` files, an
unused `.notworking.yml`) is what this directory replaces.

## Hosts

| Host | IP | Runs | Doc |
|---|---|---|---|
| worker-01 | `192.168.0.158` | pihole, monitoring, localstack, **Teleport control plane** | [192.168.0.158.md](192.168.0.158.md) |

## Deploying a change

```
scp external-services/<stack>/docker-compose.yml ubuntu@<host>:<stack-dir>/
ssh ubuntu@<host> 'cd <stack-dir> && docker compose up -d'
```

`<stack-dir>` for each stack is listed in the per-host doc.
