# ==============================================================================
# Cloud Pub/Sub Pipeline for Google Cloud Logging Ingestion
# ==============================================================================

# Dead Letter Topic for unprocessable messages
resource "google_pubsub_topic" "dead_letter_topic" {
  name    = "${var.topic_name}-dead-letter"
  project = var.project_id
}

# Main Dynatrace Logs Ingestion Topic
resource "google_pubsub_topic" "logs_topic" {
  name    = var.topic_name
  project = var.project_id
}

# Pull Subscription consumed by the Dynatrace Log Forwarder in GKE
resource "google_pubsub_subscription" "logs_subscription" {
  name    = var.subscription_name
  project = var.project_id
  topic   = google_pubsub_topic.logs_topic.name

  ack_deadline_seconds       = 60
  message_retention_duration = "604800s" # 7 days
  retain_acked_messages      = false

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_topic.id
    max_delivery_attempts = 5
  }

  expiration_policy {
    ttl = "" # Never expire
  }
}

# Project-Level Log Sink (Example forwarding system & audit logs to Pub/Sub)
resource "google_logging_project_sink" "dynatrace_log_sink" {
  count                  = var.create_project_sink ? 1 : 0
  name                   = "dynatrace-log-sink"
  project                = var.project_id
  destination            = "pubsub.googleapis.com/${google_pubsub_topic.logs_topic.id}"
  filter                 = var.log_filter
  unique_writer_identity = true
}

# Grant the Sink's unique writer identity Publisher permission on the Pub/Sub topic
resource "google_pubsub_topic_iam_member" "sink_publisher" {
  count   = var.create_project_sink ? 1 : 0
  project = var.project_id
  topic   = google_pubsub_topic.logs_topic.name
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.dynatrace_log_sink[0].writer_identity
}
