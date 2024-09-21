resource "helm_release" "crossplane" {
  depends_on       = [module.k3s] #指定依赖关系，terraform会先执行k3s，再执行helm
  name             = "crossplane"
  repository       = "https://charts.crossplane.io/stable"
  chart            = "crossplane"
  namespace        = "crossplane"
  create_namespace = true
}