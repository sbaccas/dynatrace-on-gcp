variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "location" {
  type        = string
  description = "Artifact Registry location / region"
  default     = "northamerica-northeast1"
}

variable "repository_id" {
  type        = string
  description = "Repository name"
  default     = "dynatrace-repo"
}

variable "gke_node_sa_email" {
  type        = string
  description = "Email of the GKE node service account to grant image pull access"
  default     = ""
}
