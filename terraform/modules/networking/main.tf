# ==============================================================================
# Isolated Observability VPC & Subnet
# ==============================================================================

resource "google_compute_network" "observability_vpc" {
  name                    = var.vpc_name
  project                 = var.project_id
  auto_create_subnetworks = false
  description             = "Dedicated isolated VPC for Dynatrace GKE forwarders and observability"
}

resource "google_compute_subnetwork" "gke_subnet" {
  name                     = var.subnet_name
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.observability_vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = var.pods_range_name
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = var.services_range_name
    ip_cidr_range = var.services_cidr
  }
}

# Cloud Router and Cloud NAT for GKE outbound egress to Dynatrace SaaS
resource "google_compute_router" "router" {
  name    = "${var.vpc_name}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.observability_vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.vpc_name}-nat"
  project                            = var.project_id
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = false
    filter = "ALL"
  }
}
