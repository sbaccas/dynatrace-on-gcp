output "gke_cluster_name" {
  value       = module.gke_cluster.cluster_name
  description = "GKE Cluster Name"
}

output "gke_endpoint" {
  value       = module.gke_cluster.cluster_endpoint
  description = "GKE Master Endpoint"
}

output "artifact_registry_url" {
  value       = module.artifact_registry.repository_url
  description = "Artifact Registry Docker URL"
}

output "pubsub_topic" {
  value       = module.pubsub_logging.topic_name
  description = "Pub/Sub Topic for logs"
}

output "pubsub_subscription" {
  value       = module.pubsub_logging.subscription_name
  description = "Pub/Sub Subscription for Dynatrace Log Forwarder"
}

output "metric_forwarder_sa" {
  value       = module.dynatrace_iam.metric_forwarder_sa_email
  description = "Metric Forwarder Google Service Account"
}

output "log_forwarder_sa" {
  value       = module.dynatrace_iam.log_forwarder_sa_email
  description = "Log Forwarder Google Service Account"
}

output "activegate_ips" {
  value       = module.activegate.activegate_ips
  description = "Internal IP addresses of the ActiveGate instances"
}

output "activegate_instances" {
  value       = module.activegate.activegate_instances
  description = "ActiveGate instances details (IPs and zones)"
}

output "activegate_network_zone" {
  value       = module.activegate.network_zone
  description = "Configured Dynatrace Network Zone"
}

