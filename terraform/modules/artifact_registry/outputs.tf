output "repository_id" {
  value       = google_artifact_registry_repository.docker_repo.repository_id
  description = "Artifact Registry Repository ID"
}

output "repository_name" {
  value       = google_artifact_registry_repository.docker_repo.name
  description = "Artifact Registry full resource name"
}

output "repository_url" {
  value       = "${var.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_repo.repository_id}"
  description = "Docker push/pull repository URL"
}
