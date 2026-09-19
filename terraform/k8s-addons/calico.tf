# CNI — installed first since every other addon's pods need pod networking
# to actually reach Ready (helm_release waits for rollout by default, so a
# later chart can hang/timeout if Calico isn't up yet).
resource "helm_release" "calico" {
  name             = "calico"
  repository       = "https://docs.tigera.io/calico/charts"
  chart            = "tigera-operator"
  namespace        = "tigera-operator"
  create_namespace = true
  version          = "v3.29.0" # match ansible/install_calico.yml's version for consistency

  values = [
    yamlencode({
      installation = {
        calicoNetwork = {
          ipPools = [
            {
              cidr          = var.pod_cidr
              encapsulation = "VXLANCrossSubnet"
              natOutgoing   = "Enabled"
              nodeSelector  = "all()"
            }
          ]
        }
      }
    })
  ]
}
