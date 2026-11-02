# ==============================================================================
# Google Cloud Monitoring Scoping Project Association
# ==============================================================================
# Manages the M:1 relationship between Monitored Projects and a Scoping Project.
# Limits: Up to 375 monitored projects per scoping project.

resource "google_monitoring_monitored_project" "monitored_projects" {
  for_each      = toset(var.monitored_project_ids)
  metrics_scope = var.scoping_project_id
  name          = each.value
}
