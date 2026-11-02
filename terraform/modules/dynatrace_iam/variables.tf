variable "project_id" {
  type        = string
  description = "GCP Project ID hosting GKE and Forwarders"
}

variable "scoping_project_id" {
  type        = string
  description = "GCP Scoping Project ID monitored by Metric Forwarder"
  default     = ""
}

variable "k8s_namespace" {
  type        = string
  description = "Kubernetes namespace where forwarders are deployed"
  default     = "dynatrace"
}

variable "metric_ksa_name" {
  type        = string
  description = "Kubernetes ServiceAccount name for Metric Forwarder"
  default     = "dynatrace-gcp-monitor-metrics"
}

variable "log_ksa_name" {
  type        = string
  description = "Kubernetes ServiceAccount name for Log Forwarder"
  default     = "dynatrace-gcp-monitor-logs"
}
