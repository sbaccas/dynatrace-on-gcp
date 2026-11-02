output "topic_id" {
  value       = google_pubsub_topic.logs_topic.id
  description = "Pub/Sub Topic ID"
}

output "topic_name" {
  value       = google_pubsub_topic.logs_topic.name
  description = "Pub/Sub Topic Name"
}

output "subscription_id" {
  value       = google_pubsub_subscription.logs_subscription.id
  description = "Pub/Sub Subscription ID"
}

output "subscription_name" {
  value       = google_pubsub_subscription.logs_subscription.name
  description = "Pub/Sub Subscription Name"
}

output "sink_writer_identity" {
  value       = var.create_project_sink ? google_logging_project_sink.dynatrace_log_sink[0].writer_identity : ""
  description = "Unique Service Account Writer Identity for the Log Sink"
}
