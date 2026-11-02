# ==============================================================================
# Private GKE Standard Cluster with Workload Identity
# ==============================================================================

# Custom Service Account for GKE Nodes (Principle of Least Privilege)
resource "google_service_account" "gke_node_sa" {
  account_id   = "dt-gke-node-sa"
  project      = var.project_id
  display_name = "GKE Node Service Account for Dynatrace Forwarders"
}

# Standard minimal permissions for GKE nodes
resource "google_project_iam_member" "gke_node_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_project_iam_member" "gke_node_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_project_iam_member" "gke_node_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# GKE Cluster Definition
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.location

  network    = var.network_id
  subnetwork = var.subnet_id

  deletion_protection = false

  # Delete default node pool immediately to use managed node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  # Ensure default temporary node pool satisfies organizational Shielded VM constraints
  node_config {
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  # IP Allocation Policy for VPC-native cluster
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Private Cluster Configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Authorized networks: allow public endpoints during bootstrap / testing
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "Global Authorized Network"
    }
  }

  # Add Shielded Nodes & Release Channel
  release_channel {
    channel = "REGULAR"
  }

  # Maintenance Window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "04:00"
    }
  }

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
  }
}

# Dedicated Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  project    = var.project_id
  location   = var.location
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-standard"

    service_account = google_service_account.gke_node_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      role = "dynatrace-forwarder"
    }

    tags = ["gke-dynatrace-node"]
  }
}
