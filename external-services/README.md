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

## Deploying a change to an existing stack

```
ansible-playbook -i ../ansible/external-hosts.ini ../ansible/deploy_external_service.yml \
  -e service_name=<stack> -e remote_dir=<stack-dir> --ask-become-pass
```

`<stack-dir>` for each stack is listed in the per-host doc. (Manual
`scp`/`ssh` still works if you'd rather not deal with Ansible for a
one-off change — the playbook just removes the root-owned-directory
two-step and the copy-paste.)

## Adding a brand-new service

Checklist, distilled from every gotcha hit setting up pihole/monitoring/
LocalStack the hard way:

1. **Compose file**: `external-services/<service>/docker-compose.yml`.
   Bind ports to `127.0.0.1:<port>:<port>`, not `<port>:<port>` — the
   default should be "not reachable from the LAN," with an explicit,
   documented reason for any exception (pihole's DNS port `53` is the
   only one so far: it has to be LAN-wide, that's the service's job).
2. **Cross-container calls use the Docker network, not IPs**: if this
   service needs to talk to another one on the same host (a datasource,
   an API call), point it at the other container's *service name* on
   the shared compose network (`http://prometheus:9090`, not
   `http://192.168.0.158:9090` and not `http://localhost:9090`). A LAN
   IP or `localhost` happens to work by accident whenever the other
   port is still open on `0.0.0.0`, and breaks silently the moment it
   gets locked down — this is exactly what broke Grafana's datasource.
3. **First deploy** — create the remote directory once, then deploy:
   ```
   ansible standalone -i ../ansible/external-hosts.ini -m file \
     -a "path=<remote_dir> state=directory" -b --ask-become-pass
   ansible-playbook -i ../ansible/external-hosts.ini ../ansible/deploy_external_service.yml \
     -e service_name=<service> -e remote_dir=<remote_dir> --ask-become-pass
   ```
4. **Needs remote/browser or CLI access?** Register it as a Teleport app
   rather than opening its port to the LAN — add it to
   [`../ansible/teleport_apps.yml`](../ansible/teleport_apps.yml) (the
   source of truth for "what apps should exist") and then either
   reconcile everything in that file in one pass:
   ```
   ansible-playbook -i ../ansible/external-hosts.ini ../ansible/manage_teleport_app.yml \
     --ask-become-pass
   ```
   or, for a one-off without touching the file:
   ```
   ansible-playbook -i ../ansible/external-hosts.ini ../ansible/manage_teleport_app.yml \
     -e app_name=<service> -e app_uri=http://localhost:<port>/ --ask-become-pass
   ```
   If the service does its own `Origin`/`Host` validation (anything
   that isn't naturally fine being addressed as `localhost`, e.g.
   LocalStack's CORS check), it'll 403 requests proxied through the
   Teleport domain until you allow that origin in the service's own
   config — check the app's docs for its equivalent of
   `EXTRA_CORS_ALLOWED_ORIGINS` *before* assuming it's a Teleport RBAC
   problem. A Teleport RBAC denial never reaches the backend at all —
   confirm which one you're looking at via `app.session.start` in the
   audit log (`journalctl -u teleport`): if that event exists, Teleport
   authorized it and the backend is what said no.
5. **Document it**: add a row/section to the host's `.md` doc — image,
   ports (and *why* each one is or isn't loopback-only), purpose, and
   any secret hygiene notes. Update the table in this file too if it's
   a new host.
6. **Verify**: loopback ports refuse connections from another LAN
   client but respond locally; the Teleport app URL loads
   (`https://<service>.teleport.homebytes.space`); anything the new
   service depends on cross-container still resolves correctly.
