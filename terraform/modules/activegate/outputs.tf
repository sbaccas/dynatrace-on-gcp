output "subnet_id" {
  description = "The ID of the ActiveGate subnetwork"
  value       = local.subnet_id
}

output "subnet_self_link" {
  description = "The self_link of the ActiveGate subnetwork"
  value       = local.subnet_self_link
}

output "activegate_instances" {
  description = "Map of ActiveGate instance names to their internal IP addresses and zones"
  value = {
    for idx, inst in google_compute_instance.activegate :
    inst.name => {
      internal_ip = inst.network_interface[0].network_ip
      zone        = inst.zone
    }
  }
}

output "activegate_ips" {
  description = "List of internal IP addresses assigned to the ActiveGate cluster"
  value       = [for inst in google_compute_instance.activegate : inst.network_interface[0].network_ip]
}

output "network_zone" {
  description = "The Dynatrace Network Zone configured on the ActiveGates"
  value       = var.network_zone
}
