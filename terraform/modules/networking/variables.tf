variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "region" {
  type        = string
  description = "GCP Region"
  default     = "northamerica-northeast1"
}

variable "vpc_name" {
  type        = string
  description = "VPC Name"
  default     = "dynatrace-observability-vpc"
}

variable "subnet_name" {
  type        = string
  description = "Subnet Name for GKE nodes"
  default     = "dynatrace-gke-subnet"
}

variable "subnet_cidr" {
  type        = string
  description = "Primary CIDR block for GKE nodes"
  default     = "10.20.0.0/24"
}

variable "pods_range_name" {
  type        = string
  description = "Secondary range name for Pods"
  default     = "gke-pods"
}

variable "pods_cidr" {
  type        = string
  description = "Secondary CIDR block for Pods"
  default     = "10.24.0.0/14"
}

variable "services_range_name" {
  type        = string
  description = "Secondary range name for Services"
  default     = "gke-services"
}

variable "services_cidr" {
  type        = string
  description = "Secondary CIDR block for Services"
  default     = "10.28.0.0/20"
}
