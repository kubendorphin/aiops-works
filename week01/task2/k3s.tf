module "k3s" {
  source                   = "xunleii/k3s/module" 
  k3s_version              = "v1.28.11+k3s2"
  generate_ca_certificates = true
  global_flags = [
    "--tls-san ${tencentcloud_instance.kubenode[0].public_ip}",
    "--write-kubeconfig-mode 644",
    "--disable=traefik",
    "--kube-controller-manager-arg bind-address=0.0.0.0",
    "--kube-proxy-arg metrics-bind-address=0.0.0.0",
    "--kube-scheduler-arg bind-address=0.0.0.0"
  ]
  k3s_install_env_vars = {}

  servers = {
    "k3s" = {
      ip = tencentcloud_instance.kubenode[0].private_ip
      connection = {
        timeout  = "60s"
        type     = "ssh"
        host     = tencentcloud_instance.kubenode[0].public_ip
        password = var.password
        user     = "ubuntu"
      }
    }
  }
}

resource "local_sensitive_file" "kubeconfig" {
  content  = module.k3s.kube_config
  filename = "${path.module}/config.yaml"
}
