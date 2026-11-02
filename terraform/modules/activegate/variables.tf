variable "project_id" {
  description = "The GCP project ID where ActiveGates will be deployed (e.g. workload-app-prod)"
  type        = string
}

variable "region" {
  description = "The GCP region for the ActiveGate subnet and VMs"
  type        = string
  default     = "us-central1"
}

variable "zones" {
  description = "List of availability zones across which ActiveGates will be distributed"
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b"]
}

variable "vpc_name" {
  description = "The name of the VPC network to host the ActiveGate subnet (e.g. workload-vpc)"
  type        = string
  default     = "workload-vpc"
}

variable "subnet_name" {
  description = "The name of the regional ActiveGate subnet (created or existing)"
  type        = string
  default     = "workload-activegate-subnet"
}

variable "create_subnet" {
  description = "Whether to create a new dedicated subnet (true) or target an existing subnet (false)"
  type        = bool
  default     = true
}

variable "subnet_cidr" {
  description = "CIDR range for the ActiveGate subnet (required if create_subnet = true)"
  type        = string
  default     = "10.10.2.0/24"
}

variable "instance_count" {
  description = "Number of ActiveGate VMs to deploy. If null, defaults to length of zones"
  type        = number
  default     = null
}

variable "instance_prefix" {
  description = "Name prefix for ActiveGate VM instances (e.g. dynatrace-ag, ag-stage, ag-vpc-b)"
  type        = string
  default     = "dynatrace-ag"
}

variable "assign_static_ips" {
  description = "Whether to assign deterministic static private IPs using subnet_cidr and static_ip_start_offset. Set to false to use GCP DHCP"
  type        = bool
  default     = true
}

variable "static_ip_start_offset" {
  description = "Starting host offset for static IP assignment (e.g. 10 -> .10, .11...)"
  type        = number
  default     = 10
}

variable "create_firewall_rules" {
  description = "Whether to create the ingress firewall rules for port 9999 and IAP SSH"
  type        = bool
  default     = true
}

variable "firewall_prefix" {
  description = "Optional custom prefix for firewall rule names. If empty, defaults to vpc_name"
  type        = string
  default     = ""
}

variable "network_tags" {
  description = "Network tags applied to ActiveGate instances and targeted by firewall rules"
  type        = list(string)
  default     = ["dynatrace-activegate"]
}

variable "service_account_email" {
  description = "Existing service account email to attach to ActiveGate VMs. If empty, the module creates a dedicated service account"
  type        = string
  default     = ""
}

variable "source_workload_cidrs" {
  description = "CIDR ranges of workloads permitted to send telemetry to ActiveGate on TCP port 9999"
  type        = list(string)
  default     = ["10.10.0.0/24", "10.10.2.0/24"]
}

variable "machine_type" {
  description = "GCE machine type for ActiveGate VMs"
  type        = string
  default     = "e2-standard-2"
}

variable "dynatrace_url" {
  description = "Dynatrace Tenant API base URL (e.g. https://<tenant-id>.live.dynatrace.com)"
  type        = string
}

variable "dynatrace_api_token" {
  description = "Dynatrace API token with InstallerDownload scope"
  type        = string
  sensitive   = true
}

variable "network_zone" {
  description = "Dynatrace Network Zone identifier for client-side routing (e.g. workload-prod)"
  type        = string
  default     = "workload-prod"
}


