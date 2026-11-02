variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "location" {
  type        = string
  description = "GCP Zone or Region for GKE"
  default     = "northamerica-northeast1-a"
}

variable "cluster_name" {
  type        = string
  description = "GKE Cluster Name"
  default     = "dynatrace-gke-cluster"
}

variable "network_id" {
  type        = string
  description = "VPC Network ID"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID"
}

variable "pods_range_name" {
  type        = string
  description = "Secondary range name for Pods"
}

variable "services_range_name" {
  type        = string
  description = "Secondary range name for Services"
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "CIDR block for GKE master nodes"
  default     = "172.16.0.0/28"
}

variable "machine_type" {
  type        = string
  description = "Node machine type"
  default     = "e2-standard-2"
}

variable "disk_size_gb" {
  type        = number
  description = "Node disk size in GB"
  default     = 50
}

variable "node_count" {
  type        = number
  description = "Initial number of nodes"
  default     = 2
}

variable "min_node_count" {
  type        = number
  description = "Minimum node count for autoscaling"
  default     = 1
}

variable "max_node_count" {
  type        = number
  description = "Maximum node count for autoscaling"
  default     = 4
}
