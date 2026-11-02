terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  effective_scoping_project = var.scoping_project_id != "" ? var.scoping_project_id : var.project_id
}

# 1. Networking Module (Isolated Observability VPC)
module "networking" {
  source        = "../../modules/networking"
  project_id    = var.project_id
  region        = var.region
  vpc_name      = "dynatrace-observability-vpc"
  subnet_name   = "dynatrace-gke-subnet"
  subnet_cidr   = "10.20.0.0/24"
  pods_cidr     = "10.24.0.0/14"
  services_cidr = "10.28.0.0/20"
}

# 2. GKE Cluster Module (Private Cluster with Workload Identity)
module "gke_cluster" {
  source              = "../../modules/gke_cluster"
  project_id          = var.project_id
  location            = var.zone
  cluster_name        = var.cluster_name
  network_id          = module.networking.vpc_id
  subnet_id           = module.networking.subnet_id
  pods_range_name     = module.networking.pods_range_name
  services_range_name = module.networking.services_range_name
  machine_type        = var.machine_type
  node_count          = 2
}

# 3. Artifact Registry Module (Docker Images)
module "artifact_registry" {
  source             = "../../modules/artifact_registry"
  project_id         = var.project_id
  location           = var.region
  repository_id      = "dynatrace-repo"
  gke_node_sa_email  = module.gke_cluster.node_service_account
}

# 4. Pub/Sub Logging Pipeline Module
module "pubsub_logging" {
  source              = "../../modules/pubsub_logging"
  project_id          = var.project_id
  topic_name          = "dynatrace-gcp-logs"
  subscription_name   = "dynatrace-gcp-logs-sub"
  create_project_sink = true
  log_filter          = "severity>=INFO"
}

# 5. Dynatrace IAM & Workload Identity Module (Depends on GKE Cluster for Identity Pool)
module "dynatrace_iam" {
  source             = "../../modules/dynatrace_iam"
  project_id         = var.project_id
  scoping_project_id = local.effective_scoping_project
  k8s_namespace      = "dynatrace"
  metric_ksa_name    = "dynatrace-gcp-monitor-metrics"
  log_ksa_name       = "dynatrace-gcp-monitor-logs"

  depends_on = [module.gke_cluster]
}

# 6. Optional Scoping Project Attachment (if distinct scoping project supplied)
module "scoping_project" {
  count                 = length(var.monitored_project_ids) > 0 && var.scoping_project_id != "" ? 1 : 0
  source                = "../../modules/scoping_project"
  scoping_project_id    = var.scoping_project_id
  monitored_project_ids = var.monitored_project_ids
}

# 7. Dynatrace ActiveGate Multi-Zone Cluster (in Workload Project)
module "activegate" {
  source                = "../../modules/activegate"
  project_id            = var.workload_project_id
  region                = var.region
  zones                 = var.activegate_zones
  vpc_name              = var.workload_vpc_name
  subnet_name           = var.activegate_subnet_name
  subnet_cidr           = var.activegate_subnet_cidr
  source_workload_cidrs = var.activegate_source_cidrs
  machine_type          = "e2-standard-2"
  dynatrace_url         = var.dynatrace_url
  dynatrace_api_token   = var.dynatrace_api_token
  network_zone          = var.activegate_network_zone
}


