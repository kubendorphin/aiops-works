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
