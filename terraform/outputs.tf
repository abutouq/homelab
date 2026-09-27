output "teleport_ip" {
  description = "Teleport VM IP address"
  value = module.tf_teleport_apps_01.ip_address
}