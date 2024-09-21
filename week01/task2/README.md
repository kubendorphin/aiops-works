# 使用 YAML to Infra 模式创建云 Redis 数据库。

## 安装terraform 
略

## 通过环境变量配置腾讯云api_id、api_key
```bash
cat > tf_var.env << EOF
export TF_VAR_secret_id="<your secret id>"
export TF_VAR_secret_key="<your secret key>"
EOF
source tf_var.env
```

## 创建并编辑tf文件
```bash
touch cvm.tf k3s.tf helm.tf outputs.tf variables.tf version.tf
```
编辑cvm.tf文件如下：
```hcl
# Configure the TencentCloud Provider
provider "tencentcloud" {
  region     = var.regoin
  secret_id  = var.secret_id
  secret_key = var.secret_key
}

# Get availability zones
data "tencentcloud_availability_zones_by_product" "default" {
  product = "cvm"
}

# Get availability images
data "tencentcloud_images" "default" {
  image_type = ["PUBLIC_IMAGE"]
  os_name    = "ubuntu"
}

# Get availability instance types
data "tencentcloud_instance_types" "default" {
  # 机型族
  filter {
    name   = "instance-family"
    values = ["SA5"]
  }

  cpu_core_count = 2
  memory_size    = 4
  exclude_sold_out = true
}

# Create a kubenode
resource "tencentcloud_instance" "kubenode" {
  depends_on                 = [tencentcloud_security_group_lite_rule.default]
  count                      = 1
  instance_name              = "kubenode"
  availability_zone          = data.tencentcloud_availability_zones_by_product.default.zones.0.name
  image_id                   = data.tencentcloud_images.default.images.0.image_id
  instance_type              = data.tencentcloud_instance_types.default.instance_types.0.instance_type
  system_disk_type           = "CLOUD_BSSD"
  system_disk_size           = 50
  allocate_public_ip         = true
  internet_max_bandwidth_out = 10
  instance_charge_type       = "SPOTPAID"
  orderly_security_groups    = [tencentcloud_security_group.default.id]
  password                   = var.password
}

# Create security group
resource "tencentcloud_security_group" "default" {
  name        = "tf-security-group"
  description = "make it accessible for both production and stage ports"
}

# Create security group rule allow ssh request
resource "tencentcloud_security_group_lite_rule" "default" {
  security_group_id = tencentcloud_security_group.default.id
  ingress = [
    "ACCEPT#0.0.0.0/0#22#TCP",
    "ACCEPT#0.0.0.0/0#6443#TCP",
  ]

  egress = [
    "ACCEPT#0.0.0.0/0#ALL#ALL"
  ]
}
```
编辑k3s.tf文件如下：
```hcl
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
```
编辑helm文件如下：
```hcl
resource "helm_release" "crossplane" {
  depends_on       = [module.k3s] #指定依赖关系，terraform会先执行k3s，再执行helm
  name             = "crossplane"
  repository       = "https://charts.crossplane.io/stable"
  chart            = "crossplane"
  namespace        = "crossplane"
  create_namespace = true
}
```
编辑outputs.tf文件如下：
```hcl
output "public_ip" {
  description = "vm public ip address"
  value       = tencentcloud_instance.kubenode[0].public_ip
}

output "kube_config" {
  description = "kubeconfig"
  value       = "${path.module}/config.yaml"
}

output "password" {
  description = "vm password"
  value       = var.password
}
```
编辑variables.tf如下
```hcl
variable "secret_id" {
  default = "secret_id"
}

variable "secret_key" {
  default = "secret_key"
}

variable "regoin" {
  default = "ap-hongkong"
}

variable "password" {
  default = "password123"
}
```
编辑version.tf文件如下：
```hcl
terraform {
  required_version = "> 0.13.0"
  required_providers { #引用腾讯云的库
    tencentcloud = {
      source  = "tencentcloudstack/tencentcloud"
      version = "1.81.5"
    }

    helm = { #引用helm库
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}

provider "helm" { #配置helm
  kubernetes {
    config_path = local_sensitive_file.kubeconfig.filename
  }
}
```
## 初始化
执行 terraform init
```bash
❯ terraform init
Initializing the backend...
Initializing modules...
Downloading registry.terraform.io/xunleii/k3s/module 3.4.0 for k3s...
- k3s in .terraform/modules/k3s
Initializing provider plugins...
- Finding hashicorp/helm versions matching "~> 2.14"...
- Finding latest version of hashicorp/local...
- Finding hashicorp/random versions matching "~> 3.0"...
- Finding hashicorp/tls versions matching "~> 4.0"...
- Finding hashicorp/http versions matching "~> 3.0"...
- Finding hashicorp/null versions matching "~> 3.0"...
- Finding tencentcloudstack/tencentcloud versions matching "1.81.5"...
- Installing tencentcloudstack/tencentcloud v1.81.5...
- Installed tencentcloudstack/tencentcloud v1.81.5 (signed by a HashiCorp partner, key ID 84F69E1C1BECF459)
- Installing hashicorp/helm v2.15.0...
- Installed hashicorp/helm v2.15.0 (signed by HashiCorp)
- Installing hashicorp/local v2.5.2...
- Installed hashicorp/local v2.5.2 (signed by HashiCorp)
- Installing hashicorp/random v3.6.3...
- Installed hashicorp/random v3.6.3 (signed by HashiCorp)
- Installing hashicorp/tls v4.0.6...
- Installed hashicorp/tls v4.0.6 (signed by HashiCorp)
- Installing hashicorp/http v3.4.5...
- Installed hashicorp/http v3.4.5 (signed by HashiCorp)
- Installing hashicorp/null v3.2.3...
- Installed hashicorp/null v3.2.3 (signed by HashiCorp)
Partner and community providers are signed by their developers.
If you'd like to know more about provider signing, you can read about it here:
https://www.terraform.io/docs/cli/plugins/signing.html
Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```
执行plan预览
```bash
❯ terraform plan
module.k3s.data.http.k3s_version: Reading...
data.tencentcloud_availability_zones_by_product.default: Reading...
data.tencentcloud_images.default: Reading...
data.tencentcloud_instance_types.default: Reading...
data.tencentcloud_availability_zones_by_product.default: Read complete after 0s [id=1851109860]
data.tencentcloud_images.default: Read complete after 1s [id=572099355]
data.tencentcloud_instance_types.default: Read complete after 2s [id=101746864]
module.k3s.data.http.k3s_version: Read complete after 2s [id=https://update.k3s.io/v1-release/channels]
module.k3s.data.http.k3s_installer: Reading...
module.k3s.data.http.k3s_installer: Read complete after 1s [id=https://raw.githubusercontent.com/rancher/k3s/v1.31.1+k3s1/install.sh]

Terraform used the selected providers to generate the following execution plan. Resource
actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # helm_release.crossplane will be created
  + resource "helm_release" "crossplane" {
      + atomic                     = false
      + chart                      = "crossplane"
      + cleanup_on_fail            = false
      + create_namespace           = true
      + dependency_update          = false
      + disable_crd_hooks          = false
      + disable_openapi_validation = false
      + disable_webhooks           = false
      + force_update               = false
      + id                         = (known after apply)
      + lint                       = false
      + manifest                   = (known after apply)
      + max_history                = 0
      + metadata                   = (known after apply)
      + name                       = "crossplane"
      + namespace                  = "crossplane"
      + pass_credentials           = false
      + recreate_pods              = false
      + render_subchart_notes      = true
      + replace                    = false
      + repository                 = "https://charts.crossplane.io/stable"
      + reset_values               = false
      + reuse_values               = false
      + skip_crds                  = false
      + status                     = "deployed"
      + timeout                    = 300
      + verify                     = false
      + version                    = (known after apply)
      + wait                       = true
      + wait_for_jobs              = false
    }

  # local_sensitive_file.kubeconfig will be created
  + resource "local_sensitive_file" "kubeconfig" {
      + content              = (sensitive value)
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0700"
      + file_permission      = "0700"
      + filename             = "./config.yaml"
      + id                   = (known after apply)
    }

  # tencentcloud_instance.kubenode[0] will be created
  + resource "tencentcloud_instance" "kubenode" {
      + allocate_public_ip                      = true
      + availability_zone                       = "ap-hongkong-2"
      + create_time                             = (known after apply)
      + disable_api_termination                 = false
      + disable_monitor_service                 = false
      + disable_security_service                = false
      + expired_time                            = (known after apply)
      + force_delete                            = false
      + id                                      = (known after apply)
      + image_id                                = "img-mmytdhbn"
      + instance_charge_type                    = "SPOTPAID"
      + instance_charge_type_prepaid_renew_flag = (known after apply)
      + instance_name                           = "kubenode"
      + instance_status                         = (known after apply)
      + instance_type                           = "SA5.MEDIUM4"
      + internet_charge_type                    = (known after apply)
      + internet_max_bandwidth_out              = 10
      + key_ids                                 = (known after apply)
      + key_name                                = (known after apply)
      + orderly_security_groups                 = (known after apply)
      + password                                = (sensitive value)
      + private_ip                              = (known after apply)
      + project_id                              = 0
      + public_ip                               = (known after apply)
      + running_flag                            = true
      + security_groups                         = (known after apply)
      + subnet_id                               = (known after apply)
      + system_disk_id                          = (known after apply)
      + system_disk_size                        = 50
      + system_disk_type                        = "CLOUD_BSSD"
      + vpc_id                                  = (known after apply)

      + data_disks (known after apply)
    }

  # tencentcloud_security_group.default will be created
  + resource "tencentcloud_security_group" "default" {
      + description = "make it accessible for both production and stage ports"
      + id          = (known after apply)
      + name        = "tf-security-group"
      + project_id  = (known after apply)
    }

  # tencentcloud_security_group_lite_rule.default will be created
  + resource "tencentcloud_security_group_lite_rule" "default" {
      + egress            = [
          + "ACCEPT#0.0.0.0/0#ALL#ALL",
        ]
      + id                = (known after apply)
      + ingress           = [
          + "ACCEPT#0.0.0.0/0#22#TCP",
          + "ACCEPT#0.0.0.0/0#6443#TCP",
        ]
      + security_group_id = (known after apply)
    }

  # module.k3s.null_resource.k8s_ca_certificates_install[0] will be created
  + resource "null_resource" "k8s_ca_certificates_install" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.k8s_ca_certificates_install[1] will be created
  + resource "null_resource" "k8s_ca_certificates_install" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.k8s_ca_certificates_install[2] will be created
  + resource "null_resource" "k8s_ca_certificates_install" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.k8s_ca_certificates_install[3] will be created
  + resource "null_resource" "k8s_ca_certificates_install" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.k8s_ca_certificates_install[4] will be created
  + resource "null_resource" "k8s_ca_certificates_install" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.k8s_ca_certificates_install[5] will be created
  + resource "null_resource" "k8s_ca_certificates_install" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.kubernetes_ready will be created
  + resource "null_resource" "kubernetes_ready" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.servers_drain["k3s"] will be created
  + resource "null_resource" "servers_drain" {
      + id       = (known after apply)
      + triggers = {
          + "connection_json" = (known after apply)
          + "drain_timeout"   = "0s"
          + "kubectl_cmd"     = "kubectl"
          + "server_name"     = "k3s"
        }
    }

  # module.k3s.null_resource.servers_install["k3s"] will be created
  + resource "null_resource" "servers_install" {
      + id       = (known after apply)
      + triggers = {
          + "on_immutable_changes" = (known after apply)
          + "on_new_version"       = "v1.28.11+k3s2"
        }
    }

  # module.k3s.random_password.k3s_cluster_secret will be created
  + resource "random_password" "k3s_cluster_secret" {
      + bcrypt_hash = (sensitive value)
      + id          = (known after apply)
      + length      = 48
      + lower       = true
      + min_lower   = 0
      + min_numeric = 0
      + min_special = 0
      + min_upper   = 0
      + number      = true
      + numeric     = true
      + result      = (sensitive value)
      + special     = false
      + upper       = true
    }

  # module.k3s.tls_cert_request.master_user[0] will be created
  + resource "tls_cert_request" "master_user" {
      + cert_request_pem = (known after apply)
      + id               = (known after apply)
      + key_algorithm    = (known after apply)
      + private_key_pem  = (sensitive value)

      + subject {
          + common_name  = "master-user"
          + organization = "system:masters"
        }
    }

  # module.k3s.tls_locally_signed_cert.master_user[0] will be created
  + resource "tls_locally_signed_cert" "master_user" {
      + allowed_uses          = [
          + "key_encipherment",
          + "digital_signature",
          + "client_auth",
        ]
      + ca_cert_pem           = (known after apply)
      + ca_key_algorithm      = (known after apply)
      + ca_private_key_pem    = (sensitive value)
      + cert_pem              = (known after apply)
      + cert_request_pem      = (known after apply)
      + early_renewal_hours   = 0
      + id                    = (known after apply)
      + is_ca_certificate     = false
      + ready_for_renewal     = false
      + set_subject_key_id    = false
      + validity_end_time     = (known after apply)
      + validity_period_hours = 876600
      + validity_start_time   = (known after apply)
    }

  # module.k3s.tls_private_key.kubernetes_ca[0] will be created
  + resource "tls_private_key" "kubernetes_ca" {
      + algorithm                     = "ECDSA"
      + ecdsa_curve                   = "P384"
      + id                            = (known after apply)
      + private_key_openssh           = (sensitive value)
      + private_key_pem               = (sensitive value)
      + private_key_pem_pkcs8         = (sensitive value)
      + public_key_fingerprint_md5    = (known after apply)
      + public_key_fingerprint_sha256 = (known after apply)
      + public_key_openssh            = (known after apply)
      + public_key_pem                = (known after apply)
      + rsa_bits                      = 2048
    }

  # module.k3s.tls_private_key.kubernetes_ca[1] will be created
  + resource "tls_private_key" "kubernetes_ca" {
      + algorithm                     = "ECDSA"
      + ecdsa_curve                   = "P384"
      + id                            = (known after apply)
      + private_key_openssh           = (sensitive value)
      + private_key_pem               = (sensitive value)
      + private_key_pem_pkcs8         = (sensitive value)
      + public_key_fingerprint_md5    = (known after apply)
      + public_key_fingerprint_sha256 = (known after apply)
      + public_key_openssh            = (known after apply)
      + public_key_pem                = (known after apply)
      + rsa_bits                      = 2048
    }

  # module.k3s.tls_private_key.kubernetes_ca[2] will be created
  + resource "tls_private_key" "kubernetes_ca" {
      + algorithm                     = "ECDSA"
      + ecdsa_curve                   = "P384"
      + id                            = (known after apply)
      + private_key_openssh           = (sensitive value)
      + private_key_pem               = (sensitive value)
      + private_key_pem_pkcs8         = (sensitive value)
      + public_key_fingerprint_md5    = (known after apply)
      + public_key_fingerprint_sha256 = (known after apply)
      + public_key_openssh            = (known after apply)
      + public_key_pem                = (known after apply)
      + rsa_bits                      = 2048
    }

  # module.k3s.tls_private_key.master_user[0] will be created
  + resource "tls_private_key" "master_user" {
      + algorithm                     = "ECDSA"
      + ecdsa_curve                   = "P384"
      + id                            = (known after apply)
      + private_key_openssh           = (sensitive value)
      + private_key_pem               = (sensitive value)
      + private_key_pem_pkcs8         = (sensitive value)
      + public_key_fingerprint_md5    = (known after apply)
      + public_key_fingerprint_sha256 = (known after apply)
      + public_key_openssh            = (known after apply)
      + public_key_pem                = (known after apply)
      + rsa_bits                      = 2048
    }

  # module.k3s.tls_self_signed_cert.kubernetes_ca_certs["0"] will be created
  + resource "tls_self_signed_cert" "kubernetes_ca_certs" {
      + allowed_uses          = [
          + "digital_signature",
          + "key_encipherment",
          + "cert_signing",
        ]
      + cert_pem              = (known after apply)
      + early_renewal_hours   = 0
      + id                    = (known after apply)
      + is_ca_certificate     = true
      + key_algorithm         = (known after apply)
      + private_key_pem       = (sensitive value)
      + ready_for_renewal     = false
      + set_authority_key_id  = false
      + set_subject_key_id    = false
      + validity_end_time     = (known after apply)
      + validity_period_hours = 876600
      + validity_start_time   = (known after apply)

      + subject {
          + common_name = "kubernetes-client-ca"
        }
    }

  # module.k3s.tls_self_signed_cert.kubernetes_ca_certs["1"] will be created
  + resource "tls_self_signed_cert" "kubernetes_ca_certs" {
      + allowed_uses          = [
          + "digital_signature",
          + "key_encipherment",
          + "cert_signing",
        ]
      + cert_pem              = (known after apply)
      + early_renewal_hours   = 0
      + id                    = (known after apply)
      + is_ca_certificate     = true
      + key_algorithm         = (known after apply)
      + private_key_pem       = (sensitive value)
      + ready_for_renewal     = false
      + set_authority_key_id  = false
      + set_subject_key_id    = false
      + validity_end_time     = (known after apply)
      + validity_period_hours = 876600
      + validity_start_time   = (known after apply)

      + subject {
          + common_name = "kubernetes-server-ca"
        }
    }

  # module.k3s.tls_self_signed_cert.kubernetes_ca_certs["2"] will be created
  + resource "tls_self_signed_cert" "kubernetes_ca_certs" {
      + allowed_uses          = [
          + "digital_signature",
          + "key_encipherment",
          + "cert_signing",
        ]
      + cert_pem              = (known after apply)
      + early_renewal_hours   = 0
      + id                    = (known after apply)
      + is_ca_certificate     = true
      + key_algorithm         = (known after apply)
      + private_key_pem       = (sensitive value)
      + ready_for_renewal     = false
      + set_authority_key_id  = false
      + set_subject_key_id    = false
      + validity_end_time     = (known after apply)
      + validity_period_hours = 876600
      + validity_start_time   = (known after apply)

      + subject {
          + common_name = "kubernetes-request-header-key-ca"
        }
    }

Plan: 24 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + kube_config = "./config.yaml"
  + password    = "Nf7x5t9p3q8z1K"
  + public_ip   = (known after apply)

───────────────────────────────────────────────────────────────────────────────────────────

Note: You didn't use the -out option to save this plan, so Terraform can't guarantee to
take exactly these actions if you run "terraform apply" now.
```
## 部署
执行plan无报错，所以直接执行 `terraform apply -auto-approve` 
```bash
❯ terraform apply -auto-approve
module.k3s.data.http.k3s_version: Reading...
data.tencentcloud_availability_zones_by_product.default: Reading...
data.tencentcloud_images.default: Reading...
data.tencentcloud_instance_types.default: Reading...
data.tencentcloud_availability_zones_by_product.default: Read complete after 0s [id=1851109860]
module.k3s.data.http.k3s_version: Read complete after 1s [id=https://update.k3s.io/v1-release/channels]
module.k3s.data.http.k3s_installer: Reading...
data.tencentcloud_images.default: Read complete after 0s [id=572099355]
data.tencentcloud_instance_types.default: Read complete after 1s [id=101746864]
module.k3s.data.http.k3s_installer: Read complete after 1s [id=https://raw.githubusercontent.com/rancher/k3s/v1.31.1+k3s1/install.sh]

Terraform used the selected providers to generate the following execution plan. Resource
actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # helm_release.crossplane will be created
  + resource "helm_release" "crossplane" {
      + atomic                     = false
      + chart                      = "crossplane"
      + cleanup_on_fail            = false
      + create_namespace           = true
      + dependency_update          = false
      + disable_crd_hooks          = false
      + disable_openapi_validation = false
      + disable_webhooks           = false
      + force_update               = false
      + id                         = (known after apply)
      + lint                       = false
      + manifest                   = (known after apply)
      + max_history                = 0
      + metadata                   = (known after apply)
      + name                       = "crossplane"
      + namespace                  = "crossplane"
      + pass_credentials           = false
      + recreate_pods              = false
      + render_subchart_notes      = true
      + replace                    = false
      + repository                 = "https://charts.crossplane.io/stable"
      + reset_values               = false
      + reuse_values               = false
      + skip_crds                  = false
      + status                     = "deployed"
      + timeout                    = 300
      + verify                     = false
      + version                    = "1.17.1"
      + wait                       = true
      + wait_for_jobs              = false
    }

  # local_sensitive_file.kubeconfig will be created
  + resource "local_sensitive_file" "kubeconfig" {
      + content              = (sensitive value)
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0700"
      + file_permission      = "0700"
      + filename             = "./config.yaml"
      + id                   = (known after apply)
    }

  # tencentcloud_instance.kubenode[0] will be created
  + resource "tencentcloud_instance" "kubenode" {
      + allocate_public_ip                      = true
      + availability_zone                       = "ap-hongkong-2"
      + create_time                             = (known after apply)
      + disable_api_termination                 = false
      + disable_monitor_service                 = false
      + disable_security_service                = false
      + expired_time                            = (known after apply)
      + force_delete                            = false
      + id                                      = (known after apply)
      + image_id                                = "img-mmytdhbn"
      + instance_charge_type                    = "SPOTPAID"
      + instance_charge_type_prepaid_renew_flag = (known after apply)
      + instance_name                           = "kubenode"
      + instance_status                         = (known after apply)
      + instance_type                           = "SA5.MEDIUM4"
      + internet_charge_type                    = (known after apply)
      + internet_max_bandwidth_out              = 10
      + key_ids                                 = (known after apply)
      + key_name                                = (known after apply)
      + orderly_security_groups                 = (known after apply)
      + password                                = (sensitive value)
      + private_ip                              = (known after apply)
      + project_id                              = 0
      + public_ip                               = (known after apply)
      + running_flag                            = true
      + security_groups                         = (known after apply)
      + subnet_id                               = (known after apply)
      + system_disk_id                          = (known after apply)
      + system_disk_size                        = 50
      + system_disk_type                        = "CLOUD_BSSD"
      + vpc_id                                  = (known after apply)

      + data_disks (known after apply)
    }

  # tencentcloud_security_group.default will be created
  + resource "tencentcloud_security_group" "default" {
      + description = "make it accessible for both production and stage ports"
      + id          = (known after apply)
      + name        = "tf-security-group"
      + project_id  = (known after apply)
    }

  # tencentcloud_security_group_lite_rule.default will be created
  + resource "tencentcloud_security_group_lite_rule" "default" {
      + egress            = [
          + "ACCEPT#0.0.0.0/0#ALL#ALL",
        ]
      + id                = (known after apply)
      + ingress           = [
          + "ACCEPT#0.0.0.0/0#22#TCP",
          + "ACCEPT#0.0.0.0/0#6443#TCP",
        ]
      + security_group_id = (known after apply)
    }

  # module.k3s.null_resource.k8s_ca_certificates_install[0] will be created
  + resource "null_resource" "k8s_ca_certificates_install" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.k8s_ca_certificates_install[1] will be created
  + resource "null_resource" "k8s_ca_certificates_install" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.k8s_ca_certificates_install[2] will be created
  + resource "null_resource" "k8s_ca_certificates_install" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.k8s_ca_certificates_install[3] will be created
  + resource "null_resource" "k8s_ca_certificates_install" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.k8s_ca_certificates_install[4] will be created
  + resource "null_resource" "k8s_ca_certificates_install" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.k8s_ca_certificates_install[5] will be created
  + resource "null_resource" "k8s_ca_certificates_install" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.kubernetes_ready will be created
  + resource "null_resource" "kubernetes_ready" {
      + id = (known after apply)
    }

  # module.k3s.null_resource.servers_drain["k3s"] will be created
  + resource "null_resource" "servers_drain" {
      + id       = (known after apply)
      + triggers = {
          + "connection_json" = (known after apply)
          + "drain_timeout"   = "0s"
          + "kubectl_cmd"     = "kubectl"
          + "server_name"     = "k3s"
        }
    }

  # module.k3s.null_resource.servers_install["k3s"] will be created
  + resource "null_resource" "servers_install" {
      + id       = (known after apply)
      + triggers = {
          + "on_immutable_changes" = (known after apply)
          + "on_new_version"       = "v1.28.11+k3s2"
        }
    }

  # module.k3s.random_password.k3s_cluster_secret will be created
  + resource "random_password" "k3s_cluster_secret" {
      + bcrypt_hash = (sensitive value)
      + id          = (known after apply)
      + length      = 48
      + lower       = true
      + min_lower   = 0
      + min_numeric = 0
      + min_special = 0
      + min_upper   = 0
      + number      = true
      + numeric     = true
      + result      = (sensitive value)
      + special     = false
      + upper       = true
    }

  # module.k3s.tls_cert_request.master_user[0] will be created
  + resource "tls_cert_request" "master_user" {
      + cert_request_pem = (known after apply)
      + id               = (known after apply)
      + key_algorithm    = (known after apply)
      + private_key_pem  = (sensitive value)

      + subject {
          + common_name  = "master-user"
          + organization = "system:masters"
        }
    }

  # module.k3s.tls_locally_signed_cert.master_user[0] will be created
  + resource "tls_locally_signed_cert" "master_user" {
      + allowed_uses          = [
          + "key_encipherment",
          + "digital_signature",
          + "client_auth",
        ]
      + ca_cert_pem           = (known after apply)
      + ca_key_algorithm      = (known after apply)
      + ca_private_key_pem    = (sensitive value)
      + cert_pem              = (known after apply)
      + cert_request_pem      = (known after apply)
      + early_renewal_hours   = 0
      + id                    = (known after apply)
      + is_ca_certificate     = false
      + ready_for_renewal     = false
      + set_subject_key_id    = false
      + validity_end_time     = (known after apply)
      + validity_period_hours = 876600
      + validity_start_time   = (known after apply)
    }

  # module.k3s.tls_private_key.kubernetes_ca[0] will be created
  + resource "tls_private_key" "kubernetes_ca" {
      + algorithm                     = "ECDSA"
      + ecdsa_curve                   = "P384"
      + id                            = (known after apply)
      + private_key_openssh           = (sensitive value)
      + private_key_pem               = (sensitive value)
      + private_key_pem_pkcs8         = (sensitive value)
      + public_key_fingerprint_md5    = (known after apply)
      + public_key_fingerprint_sha256 = (known after apply)
      + public_key_openssh            = (known after apply)
      + public_key_pem                = (known after apply)
      + rsa_bits                      = 2048
    }

  # module.k3s.tls_private_key.kubernetes_ca[1] will be created
  + resource "tls_private_key" "kubernetes_ca" {
      + algorithm                     = "ECDSA"
      + ecdsa_curve                   = "P384"
      + id                            = (known after apply)
      + private_key_openssh           = (sensitive value)
      + private_key_pem               = (sensitive value)
      + private_key_pem_pkcs8         = (sensitive value)
      + public_key_fingerprint_md5    = (known after apply)
      + public_key_fingerprint_sha256 = (known after apply)
      + public_key_openssh            = (known after apply)
      + public_key_pem                = (known after apply)
      + rsa_bits                      = 2048
    }

  # module.k3s.tls_private_key.kubernetes_ca[2] will be created
  + resource "tls_private_key" "kubernetes_ca" {
      + algorithm                     = "ECDSA"
      + ecdsa_curve                   = "P384"
      + id                            = (known after apply)
      + private_key_openssh           = (sensitive value)
      + private_key_pem               = (sensitive value)
      + private_key_pem_pkcs8         = (sensitive value)
      + public_key_fingerprint_md5    = (known after apply)
      + public_key_fingerprint_sha256 = (known after apply)
      + public_key_openssh            = (known after apply)
      + public_key_pem                = (known after apply)
      + rsa_bits                      = 2048
    }

  # module.k3s.tls_private_key.master_user[0] will be created
  + resource "tls_private_key" "master_user" {
      + algorithm                     = "ECDSA"
      + ecdsa_curve                   = "P384"
      + id                            = (known after apply)
      + private_key_openssh           = (sensitive value)
      + private_key_pem               = (sensitive value)
      + private_key_pem_pkcs8         = (sensitive value)
      + public_key_fingerprint_md5    = (known after apply)
      + public_key_fingerprint_sha256 = (known after apply)
      + public_key_openssh            = (known after apply)
      + public_key_pem                = (known after apply)
      + rsa_bits                      = 2048
    }

  # module.k3s.tls_self_signed_cert.kubernetes_ca_certs["0"] will be created
  + resource "tls_self_signed_cert" "kubernetes_ca_certs" {
      + allowed_uses          = [
          + "digital_signature",
          + "key_encipherment",
          + "cert_signing",
        ]
      + cert_pem              = (known after apply)
      + early_renewal_hours   = 0
      + id                    = (known after apply)
      + is_ca_certificate     = true
      + key_algorithm         = (known after apply)
      + private_key_pem       = (sensitive value)
      + ready_for_renewal     = false
      + set_authority_key_id  = false
      + set_subject_key_id    = false
      + validity_end_time     = (known after apply)
      + validity_period_hours = 876600
      + validity_start_time   = (known after apply)

      + subject {
          + common_name = "kubernetes-client-ca"
        }
    }

  # module.k3s.tls_self_signed_cert.kubernetes_ca_certs["1"] will be created
  + resource "tls_self_signed_cert" "kubernetes_ca_certs" {
      + allowed_uses          = [
          + "digital_signature",
          + "key_encipherment",
          + "cert_signing",
        ]
      + cert_pem              = (known after apply)
      + early_renewal_hours   = 0
      + id                    = (known after apply)
      + is_ca_certificate     = true
      + key_algorithm         = (known after apply)
      + private_key_pem       = (sensitive value)
      + ready_for_renewal     = false
      + set_authority_key_id  = false
      + set_subject_key_id    = false
      + validity_end_time     = (known after apply)
      + validity_period_hours = 876600
      + validity_start_time   = (known after apply)

      + subject {
          + common_name = "kubernetes-server-ca"
        }
    }

  # module.k3s.tls_self_signed_cert.kubernetes_ca_certs["2"] will be created
  + resource "tls_self_signed_cert" "kubernetes_ca_certs" {
      + allowed_uses          = [
          + "digital_signature",
          + "key_encipherment",
          + "cert_signing",
        ]
      + cert_pem              = (known after apply)
      + early_renewal_hours   = 0
      + id                    = (known after apply)
      + is_ca_certificate     = true
      + key_algorithm         = (known after apply)
      + private_key_pem       = (sensitive value)
      + ready_for_renewal     = false
      + set_authority_key_id  = false
      + set_subject_key_id    = false
      + validity_end_time     = (known after apply)
      + validity_period_hours = 876600
      + validity_start_time   = (known after apply)

      + subject {
          + common_name = "kubernetes-request-header-key-ca"
        }
    }

Plan: 24 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + kube_config = "./config.yaml"
  + password    = "Nf7x5t9p3q8z1K"
  + public_ip   = (known after apply)
module.k3s.tls_private_key.kubernetes_ca[0]: Creating...
module.k3s.random_password.k3s_cluster_secret: Creating...
module.k3s.tls_private_key.kubernetes_ca[2]: Creating...
module.k3s.tls_private_key.kubernetes_ca[1]: Creating...
module.k3s.tls_private_key.master_user[0]: Creating...
module.k3s.tls_private_key.kubernetes_ca[0]: Creation complete after 0s [id=4408ba205c6cfadfbb181fe9421fab296204979b]
module.k3s.tls_private_key.kubernetes_ca[1]: Creation complete after 0s [id=af652f10122f54adc2f752341c47239d16de4deb]
module.k3s.tls_private_key.kubernetes_ca[2]: Creation complete after 0s [id=79049a0322c6d602e7e68a87dde11963c97ce223]
module.k3s.tls_private_key.master_user[0]: Creation complete after 0s [id=0c19d7f85a3c078b9a6a3d60c7bfd73838403662]
module.k3s.random_password.k3s_cluster_secret: Creation complete after 0s [id=none]
module.k3s.tls_cert_request.master_user[0]: Creating...
module.k3s.tls_cert_request.master_user[0]: Creation complete after 0s [id=6b36d5af62b2a23c5713600dbb51024931018142]
module.k3s.tls_self_signed_cert.kubernetes_ca_certs["0"]: Creating...
module.k3s.tls_self_signed_cert.kubernetes_ca_certs["1"]: Creating...
module.k3s.tls_self_signed_cert.kubernetes_ca_certs["2"]: Creating...
module.k3s.tls_self_signed_cert.kubernetes_ca_certs["2"]: Creation complete after 0s [id=37126582405815868773113275844482999734]
module.k3s.tls_self_signed_cert.kubernetes_ca_certs["0"]: Creation complete after 0s [id=43222177607588775840571335128814925713]
module.k3s.tls_self_signed_cert.kubernetes_ca_certs["1"]: Creation complete after 0s [id=245065811835521661241159202962379215800]
module.k3s.tls_locally_signed_cert.master_user[0]: Creating...
module.k3s.tls_locally_signed_cert.master_user[0]: Creation complete after 0s [id=290409563038257958669557451747213452294]
tencentcloud_security_group.default: Creating...
tencentcloud_security_group.default: Creation complete after 1s [id=sg-b3j75q8j]
tencentcloud_security_group_lite_rule.default: Creating...
tencentcloud_security_group_lite_rule.default: Creation complete after 1s [id=sg-b3j75q8j]
tencentcloud_instance.kubenode[0]: Creating...
tencentcloud_instance.kubenode[0]: Still creating... [10s elapsed]
tencentcloud_instance.kubenode[0]: Still creating... [20s elapsed]
tencentcloud_instance.kubenode[0]: Still creating... [30s elapsed]
tencentcloud_instance.kubenode[0]: Creation complete after 32s [id=ins-rce9g0m8]
module.k3s.null_resource.k8s_ca_certificates_install[4]: Creating...
module.k3s.null_resource.k8s_ca_certificates_install[1]: Creating...
module.k3s.null_resource.k8s_ca_certificates_install[5]: Creating...
module.k3s.null_resource.k8s_ca_certificates_install[3]: Creating...
module.k3s.null_resource.k8s_ca_certificates_install[2]: Creating...
module.k3s.null_resource.k8s_ca_certificates_install[0]: Creating...
local_sensitive_file.kubeconfig: Creating...
module.k3s.null_resource.k8s_ca_certificates_install[1]: Provisioning with 'remote-exec'...
module.k3s.null_resource.k8s_ca_certificates_install[4]: Provisioning with 'remote-exec'...
module.k3s.null_resource.k8s_ca_certificates_install[3]: Provisioning with 'remote-exec'...
module.k3s.null_resource.k8s_ca_certificates_install[0]: Provisioning with 'remote-exec'...
module.k3s.null_resource.k8s_ca_certificates_install[5]: Provisioning with 'remote-exec'...
module.k3s.null_resource.k8s_ca_certificates_install[2]: Provisioning with 'remote-exec'...
module.k3s.null_resource.k8s_ca_certificates_install[0] (remote-exec): (output suppressed due to sensitive value in config)
module.k3s.null_resource.k8s_ca_certificates_install[4] (remote-exec): (output suppressed due to sensitive value in config)
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec): Connecting to remote host via SSH...
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   Host: 101.32.185.42
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   User: ubuntu
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   Password: true
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   Private key: false
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   Certificate: false
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   SSH Agent: false
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   Checking Host Key: false
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   Target Platform: unix
module.k3s.null_resource.k8s_ca_certificates_install[2] (remote-exec): (output suppressed due to sensitive value in config)
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec): Connecting to remote host via SSH...
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   Host: 101.32.185.42
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   User: ubuntu
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   Password: true
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   Private key: false
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   Certificate: false
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   SSH Agent: false
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   Checking Host Key: false
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   Target Platform: unix
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec): Connecting to remote host via SSH...
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   Host: 101.32.185.42
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   User: ubuntu
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   Password: true
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   Private key: false
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   Certificate: false
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   SSH Agent: false
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   Checking Host Key: false
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   Target Platform: unix
local_sensitive_file.kubeconfig: Creation complete after 0s [id=934862110c63aa555519b34899e14758d92d1ff3]
module.k3s.null_resource.k8s_ca_certificates_install[4]: Still creating... [10s elapsed]
module.k3s.null_resource.k8s_ca_certificates_install[3]: Still creating... [10s elapsed]
module.k3s.null_resource.k8s_ca_certificates_install[2]: Still creating... [10s elapsed]
module.k3s.null_resource.k8s_ca_certificates_install[0]: Still creating... [10s elapsed]
module.k3s.null_resource.k8s_ca_certificates_install[5]: Still creating... [10s elapsed]
module.k3s.null_resource.k8s_ca_certificates_install[1]: Still creating... [10s elapsed]
module.k3s.null_resource.k8s_ca_certificates_install[2] (remote-exec): (output suppressed due to sensitive value in config)
module.k3s.null_resource.k8s_ca_certificates_install[0] (remote-exec): (output suppressed due to sensitive value in config)
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec): Connecting to remote host via SSH...
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   Host: 101.32.185.42
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   User: ubuntu
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   Password: true
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   Private key: false
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   Certificate: false
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   SSH Agent: false
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   Checking Host Key: false
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec):   Target Platform: unix
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec): Connecting to remote host via SSH...
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   Host: 101.32.185.42
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   User: ubuntu
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   Password: true
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   Private key: false
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   Certificate: false
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   SSH Agent: false
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   Checking Host Key: false
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec):   Target Platform: unix
module.k3s.null_resource.k8s_ca_certificates_install[2] (remote-exec): (output suppressed due to sensitive value in config)
module.k3s.null_resource.k8s_ca_certificates_install[0] (remote-exec): (output suppressed due to sensitive value in config)
module.k3s.null_resource.k8s_ca_certificates_install[3] (remote-exec): Connected!
module.k3s.null_resource.k8s_ca_certificates_install[5] (remote-exec): Connected!
module.k3s.null_resource.k8s_ca_certificates_install[2]: Creation complete after 14s [id=5214679493402025021]
module.k3s.null_resource.k8s_ca_certificates_install[0]: Creation complete after 14s [id=721689657432838615]
module.k3s.null_resource.k8s_ca_certificates_install[3]: Creation complete after 14s [id=5155352567758828796]
module.k3s.null_resource.k8s_ca_certificates_install[5]: Creation complete after 14s [id=908252421448635561]
module.k3s.null_resource.k8s_ca_certificates_install[4] (remote-exec): (output suppressed due to sensitive value in config)
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec): Connecting to remote host via SSH...
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   Host: 101.32.185.42
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   User: ubuntu
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   Password: true
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   Private key: false
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   Certificate: false
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   SSH Agent: false
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   Checking Host Key: false
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec):   Target Platform: unix
module.k3s.null_resource.k8s_ca_certificates_install[1] (remote-exec): Connected!
module.k3s.null_resource.k8s_ca_certificates_install[4] (remote-exec): (output suppressed due to sensitive value in config)
module.k3s.null_resource.k8s_ca_certificates_install[4]: Creation complete after 19s [id=2533349116268705973]
module.k3s.null_resource.k8s_ca_certificates_install[1]: Creation complete after 19s [id=4724255201680391743]
module.k3s.null_resource.servers_install["k3s"]: Creating...
module.k3s.null_resource.servers_install["k3s"]: Provisioning with 'file'...
module.k3s.null_resource.servers_install["k3s"]: Provisioning with 'remote-exec'...
module.k3s.null_resource.servers_install["k3s"] (remote-exec): Connecting to remote host via SSH...
module.k3s.null_resource.servers_install["k3s"] (remote-exec):   Host: 101.32.185.42
module.k3s.null_resource.servers_install["k3s"] (remote-exec):   User: ubuntu
module.k3s.null_resource.servers_install["k3s"] (remote-exec):   Password: true
module.k3s.null_resource.servers_install["k3s"] (remote-exec):   Private key: false
module.k3s.null_resource.servers_install["k3s"] (remote-exec):   Certificate: false
module.k3s.null_resource.servers_install["k3s"] (remote-exec):   SSH Agent: false
module.k3s.null_resource.servers_install["k3s"] (remote-exec):   Checking Host Key: false
module.k3s.null_resource.servers_install["k3s"] (remote-exec):   Target Platform: unix
module.k3s.null_resource.servers_install["k3s"] (remote-exec): Connected!
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  Using v1.28.11+k3s2 as release
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  Downloading hash https://github.com/k3s-io/k3s/releases/download/v1.28.11+k3s2/sha256sum-amd64.txt
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  Downloading binary https://github.com/k3s-io/k3s/releases/download/v1.28.11+k3s2/k3s
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  Verifying binary download
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  Installing k3s to /usr/local/bin/k3s
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  Skipping installation of SELinux RPM
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  Creating /usr/local/bin/kubectl symlink to k3s
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  Creating /usr/local/bin/crictl symlink to k3s
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  Creating /usr/local/bin/ctr symlink to k3s
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  Creating killall script /usr/local/bin/k3s-killall.sh
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  Creating uninstall script /usr/local/bin/k3s-uninstall.sh
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  env: Creating environment file /etc/systemd/system/k3s.service.env
module.k3s.null_resource.servers_install["k3s"]: Still creating... [10s elapsed]
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  systemd: Creating service file /etc/systemd/system/k3s.service
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  systemd: Enabling k3s unit
module.k3s.null_resource.servers_install["k3s"] (remote-exec): Created symlink /etc/systemd/system/multi-user.target.wants/k3s.service → /etc/systemd/system/k3s.service.
module.k3s.null_resource.servers_install["k3s"] (remote-exec): [INFO]  systemd: Starting k3s
module.k3s.null_resource.servers_install["k3s"] (remote-exec): NAME   STATUS     ROLES    AGE   VERSION
module.k3s.null_resource.servers_install["k3s"] (remote-exec): k3s    NotReady   <none>   0s    v1.28.11+k3s2
module.k3s.null_resource.servers_install["k3s"]: Creation complete after 17s [id=5265849753431669956]
module.k3s.null_resource.servers_drain["k3s"]: Creating...
module.k3s.null_resource.servers_drain["k3s"]: Creation complete after 0s [id=6129387470645525797]
module.k3s.null_resource.kubernetes_ready: Creating...
module.k3s.null_resource.kubernetes_ready: Creation complete after 0s [id=8179450348109209240]
helm_release.crossplane: Creating...
helm_release.crossplane: Still creating... [10s elapsed]
helm_release.crossplane: Still creating... [20s elapsed]
helm_release.crossplane: Still creating... [30s elapsed]
helm_release.crossplane: Still creating... [40s elapsed]
helm_release.crossplane: Still creating... [50s elapsed]
helm_release.crossplane: Still creating... [1m0s elapsed]
helm_release.crossplane: Still creating... [1m10s elapsed]
helm_release.crossplane: Still creating... [1m20s elapsed]
helm_release.crossplane: Still creating... [1m30s elapsed]
helm_release.crossplane: Creation complete after 1m36s [id=crossplane]

Apply complete! Resources: 24 added, 0 changed, 0 destroyed.

Outputs:

kube_config = "./config.yaml"
password = "Nf7x5t9p3q8z1K"
public_ip = "101.32.185.42"
```
## 通过crossplane创建redis资源
### 连接并查看k8s集群
```bash
export KUBECONFIG="<当前路径的绝对路径>/config.yaml"
❯ kubectl get cs
Warning: v1 ComponentStatus is deprecated in v1.19+
NAME                 STATUS    MESSAGE   ERROR
etcd-0               Healthy   ok
controller-manager   Healthy   ok
scheduler            Healthy   ok
❯ kubectl get ns
NAME              STATUS   AGE
crossplane        Active   1m27s
default           Active   2m48s
kube-node-lease   Active   2m48s
kube-public       Active   2m48s
kube-system       Active   2m48s
```
### 创建provider资源
创建目录并创建yaml文件
```bash
mkdir yaml
cd yaml
touch provider.yaml providerConfig.yaml secret.yaml
```
编辑provider.yaml文件如下：
```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-tencentcloud
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-tencentcloud:v0.8.3
```
编辑providerConfig.yaml文件如下：
```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-tencentcloud
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-tencentcloud:v0.8.3
```
编辑secret.yaml文件如下：
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: example-creds
  namespace: crossplane
type: Opaque
stringData:
  credentials: |
    {
      "secret_id": "<your secret_id>",
      "secret_key": "<your secret_key>",
      "region": "ap-hongkong"
    }
```
创建provider
```bash
❯ kubectl apply -f provider.yaml
provider.pkg.crossplane.io/provider-tencentcloud created
❯ kubectl apply -f providerConfig.yaml
providerconfig.tencentcloud.crossplane.io/default created
❯ kubectl apply -f secret.yaml
secret/example-creds created
```
### 创建私网和子网资源
创建目录和yaml文件
```bash
mkdir redis
cd redis
touch redis-secret.yaml  redisInstance.yaml  subnet.yaml  vpc.yaml
```
编辑文件如下：
redis-secret.yaml 
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: example-creds
  namespace: default
type: Opaque
stringData:
  credentials: "12345qwert!@"
```
subnet.yaml
```yaml
apiVersion: vpc.tencentcloud.crossplane.io/v1alpha1
kind: Subnet
metadata:
  name: example-cvm-subnet
spec:
  forProvider:
    availabilityZone: "ap-hongkong-2"
    cidrBlock: "10.2.2.0/24"
    name: "crossplane-redis-subnet"
    vpcIdRef:
      name: "example-redis-vpc"
```
vpc.yaml
```yaml
apiVersion: vpc.tencentcloud.crossplane.io/v1alpha1
kind: VPC
metadata:
  name: example-cvm-vpc
spec:
  forProvider:
    cidrBlock: "10.2.0.0/16"
    name: "crossplane-redis-vpc"
```
创建vpc、subnet资源
```bash
❯ kubectl apply -f vpc.yaml
vpc.vpc.tencentcloud.crossplane.io/example-cvm-vpc created
❯ kubectl apply -f subnet.yaml
subnet.vpc.tencentcloud.crossplane.io/example-cvm-subnet created
❯ kubectl get vpc
NAME              READY   SYNCED   EXTERNAL-NAME   AGE
example-cvm-vpc   True    True     vpc-63744320    3m
❯ kubectl get subnet
NAME                 READY   SYNCED   EXTERNAL-NAME     AGE
example-cvm-subnet   True    True     subnet-monl5yaz   1m
```
### 创建redis资源
创建redis需要一个secret保存redis密码，和一个redis的yaml文件。创建文件：
```bash
touch redis-secret.yaml redisInstance.yaml
```
编辑文件内容如下：
redis-secret.yaml
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: example-creds
  namespace: default
type: Opaque
stringData:
  credentials: "12345qwert!@"
```
redisInstance.yaml（上一步看到的vpc-63744320、subnet-monl5yaz需要作为vpcId和subnetId写入redisInstance.yaml文件）
```yaml
apiVersion: redis.tencentcloud.crossplane.io/v1alpha1
kind: Instance
metadata:
  annotations:
    meta.upbound.io/example-id: redis/v1alpha1/instance
  labels:
    testing.upbound.io/example-name: crossplane-redis
  name: crossplane-redis
spec:
  forProvider:
    availabilityZone: ap-hongkong-2
    chargeType: "POSTPAID"
    memSize: 512
    name: terrform_demo
    passwordSecretRef:
      key: credentials
      name: example-creds
      namespace: default
    port: 6379
    redisReplicasNum: 1
    redisShardNum: 1
    subnetId: subnet-monl5yaz
    typeId: 2
    vpcId: vpc-63744320
```
创建资源
```bash
❯ kubectl apply -f redis-secret.yaml
secret/example-creds created
❯ kubectl apply -f redisInstance.yaml
instance.redis.tencentcloud.crossplane.io/crossplane-redis created
```
资源创建完成。
```bash
❯ kubectl get instance.redis.tencentcloud.crossplane.io/crossplane-redis
NAME               READY   SYNCED   EXTERNAL-NAME   AGE
crossplane-redis   True    True     crs-p9z07bzb    3m
```
## 销毁资源
先销毁crossplane创建的资源
```bash
❯ kubectl delete -f redisInstance.yaml
instance.redis.tencentcloud.crossplane.io "crossplane-redis" deleted
❯ kubectl delete -f redis-secret.yaml
secret "example-creds" deleted
❯ kubectl delete -f subnet.yaml
subnet.vpc.tencentcloud.crossplane.io "example-cvm-subnet" deleted
❯ kubectl delete -f vpc.yaml
vpc.vpc.tencentcloud.crossplane.io "example-cvm-vpc" deleted
```
销毁terraform创建的资源
```bash
❯ terraform state list
data.tencentcloud_availability_zones_by_product.default
data.tencentcloud_images.default
data.tencentcloud_instance_types.default
helm_release.crossplane
local_sensitive_file.kubeconfig
tencentcloud_instance.kubenode[0]
tencentcloud_security_group.default
tencentcloud_security_group_lite_rule.default
module.k3s.data.http.k3s_installer
module.k3s.data.http.k3s_version
module.k3s.null_resource.k8s_ca_certificates_install[0]
module.k3s.null_resource.k8s_ca_certificates_install[1]
module.k3s.null_resource.k8s_ca_certificates_install[2]
module.k3s.null_resource.k8s_ca_certificates_install[3]
module.k3s.null_resource.k8s_ca_certificates_install[4]
module.k3s.null_resource.k8s_ca_certificates_install[5]
module.k3s.null_resource.kubernetes_ready
module.k3s.null_resource.servers_drain["k3s"]
module.k3s.null_resource.servers_install["k3s"]
module.k3s.random_password.k3s_cluster_secret
module.k3s.tls_cert_request.master_user[0]
module.k3s.tls_locally_signed_cert.master_user[0]
module.k3s.tls_private_key.kubernetes_ca[0]
module.k3s.tls_private_key.kubernetes_ca[1]
module.k3s.tls_private_key.kubernetes_ca[2]
module.k3s.tls_private_key.master_user[0]
module.k3s.tls_self_signed_cert.kubernetes_ca_certs["0"]
module.k3s.tls_self_signed_cert.kubernetes_ca_certs["1"]
module.k3s.tls_self_signed_cert.kubernetes_ca_certs["2"]
❯ terraform destroy -auto-approve
```