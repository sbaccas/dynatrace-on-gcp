variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "topic_name" {
  type        = string
  description = "Pub/Sub Topic name for logs"
  default     = "dynatrace-gcp-logs"
}

variable "subscription_name" {
  type        = string
  description = "Pub/Sub Subscription name"
  default     = "dynatrace-gcp-logs-sub"
}

variable "create_project_sink" {
  type        = bool
  description = "Whether to create a project-level log sink"
  default     = true
}

variable "log_filter" {
  type        = string
  description = "Logging filter query for sink"
  default     = "severity>=INFO"
}
