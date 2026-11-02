variable "scoping_project_id" {
  type        = string
  description = "Project ID of the dedicated Cloud Monitoring Scoping Project"
}

variable "monitored_project_ids" {
  type        = list(string)
  description = "List of project IDs to attach to the scoping project (Max 375)"
  default     = []
}
