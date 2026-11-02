# ==============================================================================
# Dynatrace Forwarders IAM & Workload Identity
# ==============================================================================

# 1. Metric Forwarder Service Account
resource "google_service_account" "metric_forwarder_sa" {
  account_id   = "dt-metric-forwarder"
  project      = var.project_id
  display_name = "Dynatrace Metric Forwarder Service Account"
}

# Grant Monitoring Viewer on the target Scoping Project
resource "google_project_iam_member" "metric_forwarder_monitoring" {
  project = var.scoping_project_id != "" ? var.scoping_project_id : var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.metric_forwarder_sa.email}"
}

# Workload Identity binding for Metric Forwarder
resource "google_service_account_iam_member" "metric_forwarder_wli" {
  service_account_id = google_service_account.metric_forwarder_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.metric_ksa_name}]"
}

# 2. Log Forwarder Service Account
resource "google_service_account" "log_forwarder_sa" {
  account_id   = "dt-log-forwarder"
  project      = var.project_id
  display_name = "Dynatrace Log Forwarder Service Account"
}

# Grant Pub/Sub Subscriber permission
resource "google_project_iam_member" "log_forwarder_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.log_forwarder_sa.email}"
}

# Workload Identity binding for Log Forwarder
resource "google_service_account_iam_member" "log_forwarder_wli" {
  service_account_id = google_service_account.log_forwarder_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.log_ksa_name}]"
}
