# 实践 Terraform，开通腾讯云虚拟机，并安装 Docker。

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
touch main.tf outputs.tf variables.tf version.tf
```
编辑main.tf文件如下：
```hcl
# Configure the TencentCloud Provider
provider "tencentcloud" {
  region     = var.region
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

# Create a cvm
resource "tencentcloud_instance" "docker_host" {
  depends_on                 = [tencentcloud_security_group_lite_rule.default]
  count                      = 1
  instance_name              = "docker_host"
  availability_zone          = data.tencentcloud_availability_zones_by_product.default.zones.0.name
  image_id                   = data.tencentcloud_images.default.images.0.image_id
  instance_type              = data.tencentcloud_instance_types.default.instance_types.0.instance_type
  system_disk_type           = "CLOUD_BSSD"
  system_disk_size           = 20
  allocate_public_ip         = true
  internet_max_bandwidth_out = 10
  instance_charge_type       = "SPOTPAID"
  orderly_security_groups    = [tencentcloud_security_group.default.id]
  password                   = var.password

  # ssh config
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = self.public_ip
      user        = "ubuntu" # Ubuntu的默认用户
      password    = var.password
      timeout     = "30s"
    }

    #exec command
    inline = [
      "curl -fsSL https://get.docker.com -o get-docker.sh",
      "sudo sh get-docker.sh",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo docker version > /tmp/docker_version.txt"
    ]
  }
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

resource "null_resource" "docker_version" {
  depends_on = [tencentcloud_instance.docker_host]

  # connection {
  #   type        = "ssh"
  #   host        = self.public_ip
  #   user        = "ubuntu" # Ubuntu的默认用户
  #   password    = self.password
  #   timeout     = "30s"
  # }

  provisioner "local-exec" {
    when    = create
    command = "scp -o StrictHostKeyChecking=no ubuntu@${tencentcloud_instance.docker_host[0].public_ip}:/tmp/docker_version.txt ${path.module}/docker_version.txt"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -f ${path.module}/docker_version.txt"
  }
}
```
编辑out.tf文件如下：
```hcl
output "public_ip" {
  description = "vm public ip address"
  value       = tencentcloud_instance.docker_host[0].public_ip
}

output "password" {
  description = "vm password"
  value       = var.password
}

output "docker_version" {
  depends_on = [null_resource.docker_version]
  value = file("./docker_version.txt")
  #value = "${file(format("%s/docker_version.txt", tencentcloud_instance.docker_host[0].public_ip))}"
}
```
编辑variables.tf文件如下
```hcl
variable "secret_id" {
  default = "secret_id"
}

variable "secret_key" {
  default = "secret_key"
}

variable "region" {
  default = "ap-hongkong"
}

variable "password" {
  default = "Nf7x5t9p3q8z1K"
}
```
编辑version.tf文件如下：
```hcl
terraform {
  required_version = "> 0.13.0"
  required_providers { 
    tencentcloud = {
      source  = "tencentcloudstack/tencentcloud"
      version = "1.81.5"
    }

  }
}
```

## 执行
初始化
```bash
❯ terraform init
Initializing the backend...
Initializing provider plugins...
- Finding tencentcloudstack/tencentcloud versions matching "1.81.5"...
- Finding latest version of hashicorp/local...
- Finding latest version of hashicorp/null...
- Installing tencentcloudstack/tencentcloud v1.81.5...
- Installed tencentcloudstack/tencentcloud v1.81.5 (signed by a HashiCorp partner, key ID 84F69E1C1BECF459)
- Installing hashicorp/local v2.5.2...
- Installed hashicorp/local v2.5.2 (signed by HashiCorp)
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
执行预览
```bash
❯ terraform plan
data.tencentcloud_availability_zones_by_product.default: Reading...
data.tencentcloud_instance_types.default: Reading...
data.tencentcloud_images.default: Reading...
data.tencentcloud_availability_zones_by_product.default: Read complete after 1s [id=1851109860]
data.tencentcloud_images.default: Read complete after 2s [id=572099355]
data.tencentcloud_instance_types.default: Read complete after 2s [id=101746864]

Terraform used the selected providers to generate the following execution plan. Resource actions
are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # null_resource.docker_version will be created
  + resource "null_resource" "docker_version" {
      + id = (known after apply)
    }

  # tencentcloud_instance.docker_host[0] will be created
  + resource "tencentcloud_instance" "docker_host" {
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
      + instance_name                           = "docker_host"
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
      + system_disk_size                        = 20
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

Plan: 4 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + docker_version = (known after apply)
  + password       = "Nf7x5t9p3q8z1K"
  + public_ip      = (known after apply)

───────────────────────────────────────────────────────────────────────────────────────────────────

Note: You didn't use the -out option to save this plan, so Terraform can't guarantee to take
exactly these actions if you run "terraform apply" now.
```
## 部署
```bash
terraform apply -auto-approve
data.tencentcloud_images.default: Reading...
data.tencentcloud_instance_types.default: Reading...
data.tencentcloud_availability_zones_by_product.default: Reading...
data.tencentcloud_availability_zones_by_product.default: Read complete after 0s [id=1851109860]
data.tencentcloud_images.default: Read complete after 0s [id=572099355]
data.tencentcloud_instance_types.default: Read complete after 1s [id=101746864]

Terraform used the selected providers to generate the following execution plan. Resource actions
are indicated with the following symbols:
  + create
...
...
tencentcloud_instance.docker_host[0]: Still creating... [1m20s elapsed]
tencentcloud_instance.docker_host[0] (remote-exec): + sh -c docker version
tencentcloud_instance.docker_host[0] (remote-exec): Client: Docker Engine - Community
tencentcloud_instance.docker_host[0] (remote-exec):  Version:           27.3.0
tencentcloud_instance.docker_host[0] (remote-exec):  API version:       1.47
tencentcloud_instance.docker_host[0] (remote-exec):  Go version:        go1.22.7
tencentcloud_instance.docker_host[0] (remote-exec):  Git commit:        e85edf8
tencentcloud_instance.docker_host[0] (remote-exec):  Built:             Thu Sep 19 14:25:51 2024
tencentcloud_instance.docker_host[0] (remote-exec):  OS/Arch:           linux/amd64
tencentcloud_instance.docker_host[0] (remote-exec):  Context:           default

tencentcloud_instance.docker_host[0] (remote-exec): Server: Docker Engine - Community
tencentcloud_instance.docker_host[0] (remote-exec):  Engine:
tencentcloud_instance.docker_host[0] (remote-exec):   Version:          27.3.0
tencentcloud_instance.docker_host[0] (remote-exec):   API version:      1.47 (minimum version 1.24)
tencentcloud_instance.docker_host[0] (remote-exec):   Go version:       go1.22.7
tencentcloud_instance.docker_host[0] (remote-exec):   Git commit:       41ca978
tencentcloud_instance.docker_host[0] (remote-exec):   Built:            Thu Sep 19 14:25:51 2024
tencentcloud_instance.docker_host[0] (remote-exec):   OS/Arch:          linux/amd64
tencentcloud_instance.docker_host[0] (remote-exec):   Experimental:     false
tencentcloud_instance.docker_host[0] (remote-exec):  containerd:
tencentcloud_instance.docker_host[0] (remote-exec):   Version:          1.7.22
tencentcloud_instance.docker_host[0] (remote-exec):   GitCommit:        7f7fdf5fed64eb6a7caf99b3e12efcf9d60e311c
tencentcloud_instance.docker_host[0] (remote-exec):  runc:
tencentcloud_instance.docker_host[0] (remote-exec):   Version:          1.1.14
tencentcloud_instance.docker_host[0] (remote-exec):   GitCommit:        v1.1.14-0-g2c9f560
tencentcloud_instance.docker_host[0] (remote-exec):  docker-init:
tencentcloud_instance.docker_host[0] (remote-exec):   Version:          0.19.0
tencentcloud_instance.docker_host[0] (remote-exec):   GitCommit:        de40ad0
```
## 销毁
```bash
❯ terraform destroy -auto-approve
data.tencentcloud_images.default: Reading...
tencentcloud_security_group.default: Refreshing state... [id=sg-8kpcenmj]
data.tencentcloud_availability_zones_by_product.default: Reading...
data.tencentcloud_instance_types.default: Reading...
data.tencentcloud_availability_zones_by_product.default: Read complete after 0s [id=1851109860]
tencentcloud_security_group_lite_rule.default: Refreshing state... [id=sg-8kpcenmj]
data.tencentcloud_images.default: Read complete after 1s [id=572099355]
data.tencentcloud_instance_types.default: Read complete after 1s [id=101746864]
tencentcloud_instance.docker_host[0]: Refreshing state... [id=ins-i3xeqoge]
null_resource.docker_version: Refreshing state... [id=4537441731426549496]

Terraform used the selected providers to generate the following execution plan. Resource actions
are indicated with the following symbols:
  - destroy

Terraform will perform the following actions:

  # null_resource.docker_version will be destroyed
  - resource "null_resource" "docker_version" {
      - id = "4537441731426549496" -> null
    }

  # tencentcloud_instance.docker_host[0] will be destroyed
  - resource "tencentcloud_instance" "docker_host" {
      - allocate_public_ip                      = true -> null
      - availability_zone                       = "ap-hongkong-2" -> null
      - create_time                             = "2024-09-20T10:54:45Z" -> null
      - disable_api_termination                 = false -> null
      - disable_monitor_service                 = false -> null
      - disable_security_service                = false -> null
      - force_delete                            = false -> null
      - id                                      = "ins-i3xeqoge" -> null
      - image_id                                = "img-mmytdhbn" -> null
      - instance_charge_type                    = "SPOTPAID" -> null
      - instance_name                           = "docker_host" -> null
      - instance_status                         = "RUNNING" -> null
      - instance_type                           = "SA5.MEDIUM4" -> null
      - internet_charge_type                    = "TRAFFIC_POSTPAID_BY_HOUR" -> null
      - internet_max_bandwidth_out              = 10 -> null
      - key_ids                                 = [
          - null,
        ] -> null
      - orderly_security_groups                 = [
          - "sg-8kpcenmj",
        ] -> null
      - password                                = (sensitive value) -> null
      - private_ip                              = "172.19.0.8" -> null
      - project_id                              = 0 -> null
      - public_ip                               = "129.226.175.78" -> null
      - running_flag                            = true -> null
      - security_groups                         = [
          - "sg-8kpcenmj",
        ] -> null
      - subnet_id                               = "subnet-15z3xg9z" -> null
      - system_disk_id                          = "disk-piktn9uq" -> null
      - system_disk_size                        = 20 -> null
      - system_disk_type                        = "CLOUD_BSSD" -> null
      - tags                                    = {} -> null
      - vpc_id                                  = "vpc-c0hqskts" -> null
        # (4 unchanged attributes hidden)
    }

  # tencentcloud_security_group.default will be destroyed
  - resource "tencentcloud_security_group" "default" {
      - description = "make it accessible for both production and stage ports" -> null
      - id          = "sg-8kpcenmj" -> null
      - name        = "tf-security-group" -> null
      - project_id  = 0 -> null
      - tags        = {} -> null
    }

  # tencentcloud_security_group_lite_rule.default will be destroyed
  - resource "tencentcloud_security_group_lite_rule" "default" {
      - egress            = [
          - "ACCEPT#0.0.0.0/0#ALL#ALL",
        ] -> null
      - id                = "sg-8kpcenmj" -> null
      - ingress           = [
          - "ACCEPT#0.0.0.0/0#22#TCP",
          - "ACCEPT#0.0.0.0/0#6443#TCP",
        ] -> null
      - security_group_id = "sg-8kpcenmj" -> null
    }

Plan: 0 to add, 0 to change, 4 to destroy.

Changes to Outputs:
  - docker_version = "" -> null
  - password       = "Nf7x5t9p3q8z1K" -> null
  - public_ip      = "129.226.175.78" -> null
null_resource.docker_version: Destroying... [id=4537441731426549496]
null_resource.docker_version: Destruction complete after 0s
tencentcloud_instance.docker_host[0]: Destroying... [id=ins-i3xeqoge]
tencentcloud_instance.docker_host[0]: Destruction complete after 5s
tencentcloud_security_group_lite_rule.default: Destroying... [id=sg-8kpcenmj]
tencentcloud_security_group_lite_rule.default: Destruction complete after 1s
tencentcloud_security_group.default: Destroying... [id=sg-8kpcenmj]
tencentcloud_security_group.default: Destruction complete after 2s

Destroy complete! Resources: 4 destroyed.
```
