output "vpc_id" {
  value       = google_compute_network.observability_vpc.id
  description = "VPC Network ID"
}

output "vpc_name" {
  value       = google_compute_network.observability_vpc.name
  description = "VPC Network Name"
}

output "subnet_id" {
  value       = google_compute_subnetwork.gke_subnet.id
  description = "GKE Node Subnet ID"
}

output "subnet_name" {
  value       = google_compute_subnetwork.gke_subnet.name
  description = "GKE Node Subnet Name"
}

output "pods_range_name" {
  value       = var.pods_range_name
  description = "Secondary range name for Pods"
}

output "services_range_name" {
  value       = var.services_range_name
  description = "Secondary range name for Services"
}
