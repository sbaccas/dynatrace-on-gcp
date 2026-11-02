output "scoping_project_id" {
  value       = var.scoping_project_id
  description = "The Scoping Project ID"
}

output "attached_monitored_projects" {
  value       = [for p in google_monitoring_monitored_project.monitored_projects : p.name]
  description = "List of monitored project IDs attached to this metrics scope"
}
