output "cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE Cluster Name"
}

output "cluster_id" {
  value       = google_container_cluster.primary.id
  description = "GKE Cluster ID"
}

output "cluster_endpoint" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE Cluster API Endpoint"
}

output "cluster_ca_certificate" {
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  description = "GKE Cluster CA Certificate"
  sensitive   = true
}

output "node_service_account" {
  value       = google_service_account.gke_node_sa.email
  description = "GKE Node Pool Service Account Email"
}
