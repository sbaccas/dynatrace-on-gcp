output "metric_forwarder_sa_email" {
  value       = google_service_account.metric_forwarder_sa.email
  description = "GSA email for Metric Forwarder"
}

output "log_forwarder_sa_email" {
  value       = google_service_account.log_forwarder_sa.email
  description = "GSA email for Log Forwarder"
}
