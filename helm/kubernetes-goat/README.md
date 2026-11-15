# kubernetes-goat

[Kubernetes Goat](https://github.com/madhuakula/kubernetes-goat) converted as-is into
one Helm chart. It replaces upstream's `setup-kubernetes-goat.sh` and
`teardown-kubernetes-goat.sh` with a single `helm install` and `helm uninstall`.

> **Intentionally vulnerable.** The bugs and misconfigurations are the point. Don't
> "fix" the manifests unless you're working through a scenario's remediation.

## Layout

| Path | Source (upstream) |
|---|---|
| `templates/<scenario>.yaml` | `scenarios/<scenario>/*.yaml`, wrapped in `{{- if .Values.<scenario>.enabled }}`; `namespace: default` → `{{ .Release.Namespace }}` |
| `charts/metadata-db/` | `scenarios/metadata-db/` (upstream's own Helm chart), unchanged |
| `access-kubernetes-goat.sh` | `access-kubernetes-goat.sh`; `default` → `$GOAT_NAMESPACE` (default `kubernetes-goat`) |

Unlike upstream, the lab runs in its own `kubernetes-goat` namespace instead of `default`.
Where a walkthrough says `default`, use `kubernetes-goat`. `secure-middleware`,
`big-monolith` and `kube-system/superadmin` keep their upstream namespaces.

The only value that doesn't come from upstream is `metadata-db.fullnameOverride: metadata-db`.
Without it, the umbrella release would rename the Service to `kubernetes-goat-metadata-db`,
which the SSRF scenario wouldn't find.

Like upstream's setup script, this chart doesn't deploy `kube-bench-security`,
`docker-bench-security` or `kyverno-namespace-exec-block`. Apply those from the upstream
repo when a scenario calls for them.

## Install

```bash
helm upgrade --install kubernetes-goat helm/kubernetes-goat -n kubernetes-goat --create-namespace
kubectl get pods -A
bash helm/kubernetes-goat/access-kubernetes-goat.sh   # http://127.0.0.1:1234
```

## Uninstall

```bash
helm uninstall kubernetes-goat -n kubernetes-goat
```
