# kubernetes-goat

[Kubernetes Goat](https://github.com/madhuakula/kubernetes-goat) converted as-is into
one Helm chart. It replaces upstream's `setup-kubernetes-goat.sh` and
`teardown-kubernetes-goat.sh` with a single `helm install` and `helm uninstall`.

> **Intentionally vulnerable.** The bugs and misconfigurations are the point. Don't
> "fix" the manifests unless you're working through a scenario's remediation.

## Layout

| Path | Source (upstream) |
|---|---|
| `templates/<scenario>.yaml` | `scenarios/<scenario>/*.yaml`, byte-for-byte, wrapped in `{{- if .Values.<scenario>.enabled }}` |
| `charts/metadata-db/` | `scenarios/metadata-db/` (upstream's own Helm chart), unchanged |
| `access-kubernetes-goat.sh` | `access-kubernetes-goat.sh`, unchanged |

The only value that doesn't come from upstream is `metadata-db.fullnameOverride: metadata-db`.
Without it, the umbrella release would rename the Service to `kubernetes-goat-metadata-db`,
which the SSRF scenario wouldn't find.

Like upstream's setup script, this chart doesn't deploy `kube-bench-security`,
`docker-bench-security` or `kyverno-namespace-exec-block`. Apply those from the upstream
repo when a scenario calls for them.

## Install

```bash
helm upgrade --install kubernetes-goat helm/kubernetes-goat -n default
kubectl get pods -A
bash helm/kubernetes-goat/access-kubernetes-goat.sh   # http://127.0.0.1:1234
```

## Uninstall

```bash
helm uninstall kubernetes-goat -n default
```
