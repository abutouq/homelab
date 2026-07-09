# Standalone Docker Compose Hosts

Services that run via Docker Compose directly on a host, outside the
Kubernetes cluster documented in the root [README.md](../README.md) and
provisioned by [ansible/](../ansible/). The compose files here are the
source of truth — edit them in this repo, then copy/deploy to the host,
rather than editing in place on the server. That drift (manual `.bak`
files, an unused `.notworking.yml`) is what this directory replaces.

## Hosts

| Host | IP | Stacks | Doc |
|---|---|---|---|
| worker-01 | `192.168.0.158` | pihole, monitoring, localstack (planned) | [192.168.0.158.md](192.168.0.158.md) |

## Deploying a change

```
scp external-services/<stack>/docker-compose.yml ubuntu@<host>:<stack-dir>/
ssh ubuntu@<host> 'cd <stack-dir> && docker compose up -d'
```

`<stack-dir>` for each stack is listed in the per-host doc.
