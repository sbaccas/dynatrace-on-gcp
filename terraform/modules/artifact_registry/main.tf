# ==============================================================================
# Google Artifact Registry (Docker Repository)
# ==============================================================================

resource "google_artifact_registry_repository" "docker_repo" {
  repository_id = var.repository_id
  location      = var.location
  project       = var.project_id
  format        = "DOCKER"
  description   = "Container images for Dynatrace forwarders and observability canary workloads"

  docker_config {
    immutable_tags = false
  }

  labels = {
    env  = "prod"
    role = "observability"
  }
}

# Grant GKE node service account reader access to pull images from Artifact Registry
resource "google_artifact_registry_repository_iam_member" "gke_node_reader" {
  project    = var.project_id
  location   = var.location
  repository = google_artifact_registry_repository.docker_repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.gke_node_sa_email}"
}
