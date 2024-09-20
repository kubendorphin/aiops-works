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