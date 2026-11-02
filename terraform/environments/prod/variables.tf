variable "project_id" {
  type        = string
  description = "GCP Project ID hosting the Dynatrace platform infrastructure"
  default     = "dynatrace-platform-prod"
}

variable "region" {
  type        = string
  description = "GCP Region"
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "GCP Zone"
  default     = "us-central1-a"
}

variable "scoping_project_id" {
  type        = string
  description = "Scoping project for GCP Cloud Monitoring metrics (leave empty if using project_id)"
  default     = ""
}

variable "monitored_project_ids" {
  type        = list(string)
  description = "Projects to attach to the monitoring scope"
  default     = []
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name"
  default     = "dynatrace-forwarder-gke"
}

variable "machine_type" {
  type        = string
  description = "Node machine type"
  default     = "e2-standard-2"
}

variable "workload_project_id" {
  type        = string
  description = "GCP Project ID hosting workload VMs and ActiveGate"
  default     = "workload-app-prod"
}

variable "workload_vpc_name" {
  type        = string
  description = "Name of the workload VPC hosting ActiveGate"
  default     = "workload-vpc"
}

variable "activegate_zones" {
  type        = list(string)
  description = "Availability zones for multi-zone ActiveGate deployment"
  default     = ["us-central1-a", "us-central1-b"]
}

variable "activegate_subnet_name" {
  type        = string
  description = "Regional subnet name for ActiveGate cluster"
  default     = "workload-activegate-subnet"
}

variable "activegate_subnet_cidr" {
  type        = string
  description = "CIDR block for the dedicated ActiveGate subnet"
  default     = "10.10.2.0/24"
}

variable "activegate_source_cidrs" {
  type        = list(string)
  description = "CIDR ranges of workload subnets permitted to connect to ActiveGate on TCP 9999"
  default     = ["10.10.0.0/24", "10.10.2.0/24"]
}

variable "dynatrace_url" {
  type        = string
  description = "Dynatrace Tenant API base URL (set via terraform.tfvars or TF_VAR_dynatrace_url)"
}

variable "dynatrace_api_token" {
  type        = string
  description = "Dynatrace API token with InstallerDownload scope (set via terraform.tfvars or TF_VAR_dynatrace_api_token)"
  sensitive   = true
}

variable "activegate_network_zone" {
  type        = string
  description = "Dynatrace Network Zone identifier"
  default     = "workload-prod"
}


