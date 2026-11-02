# ==============================================================================
# Dynatrace ActiveGate Infrastructure Module
# - Supports Dedicated Regional Subnet Creation OR Targeting Existing Subnet
# - Highly Available Multi-Zone Deployment across N Availability Zones
# - Zero Public IP Egress via Cloud NAT
# - Automated ActiveGate Installation via Metadata Startup Script
# - Flexible Parameterization for Repeatable Multi-Subnet Deployments
# ==============================================================================

locals {
  instance_count = var.instance_count != null ? var.instance_count : length(var.zones)

  subnet_self_link = var.create_subnet ? google_compute_subnetwork.activegate_subnet[0].self_link : data.google_compute_subnetwork.existing_subnet[0].self_link
  subnet_id        = var.create_subnet ? google_compute_subnetwork.activegate_subnet[0].id : data.google_compute_subnetwork.existing_subnet[0].id

  sa_email = var.service_account_email != "" ? var.service_account_email : (length(google_service_account.activegate_sa) > 0 ? google_service_account.activegate_sa[0].email : "")

  fw_prefix = var.firewall_prefix != "" ? var.firewall_prefix : var.vpc_name
}

# 1. Existing Subnetwork Data Source (used when create_subnet = false)
data "google_compute_subnetwork" "existing_subnet" {
  count   = var.create_subnet ? 0 : 1
  project = var.project_id
  region  = var.region
  name    = var.subnet_name
}

# 2. Dedicated Regional ActiveGate Subnet (created when create_subnet = true)
resource "google_compute_subnetwork" "activegate_subnet" {
  count                    = var.create_subnet ? 1 : 0
  project                  = var.project_id
  name                     = var.subnet_name
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = var.vpc_name
  private_ip_google_access = true
  description              = "Dedicated regional subnet for Dynatrace ActiveGate cluster in ${var.region}"
}

# 3. Service Account for ActiveGate Instances
resource "google_service_account" "activegate_sa" {
  count        = var.service_account_email == "" ? 1 : 0
  project      = var.project_id
  account_id   = var.instance_prefix == "dynatrace-ag" ? "dt-activegate-sa" : "${var.instance_prefix}-sa"
  display_name = "Dynatrace ActiveGate Service Account"
  description  = "Service account attached to Dynatrace ActiveGate GCE instances"
}

resource "google_project_iam_member" "activegate_logging" {
  count   = var.service_account_email == "" ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.activegate_sa[0].email}"
}

resource "google_project_iam_member" "activegate_monitoring" {
  count   = var.service_account_email == "" ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.activegate_sa[0].email}"
}

# 4. Ingress Firewall Rule for ActiveGate (Port 9999 from workload subnets)
resource "google_compute_firewall" "activegate_ingress_9999" {
  count       = var.create_firewall_rules ? 1 : 0
  project     = var.project_id
  name        = var.instance_prefix == "dynatrace-ag" ? "${var.vpc_name}-allow-activegate-9999" : "${local.fw_prefix}-${var.instance_prefix}-allow-9999"
  network     = var.vpc_name
  description = "Allow inbound Dynatrace OneAgent traffic on port 9999 to ActiveGate instances"

  direction     = "INGRESS"
  priority      = 1000
  source_ranges = var.source_workload_cidrs
  target_tags   = var.network_tags

  allow {
    protocol = "tcp"
    ports    = ["9999"]
  }
}

# 5. Ingress Firewall Rule for IAP SSH (Port 22 from Google IAP range)
resource "google_compute_firewall" "activegate_ingress_iap" {
  count       = var.create_firewall_rules ? 1 : 0
  project     = var.project_id
  name        = var.instance_prefix == "dynatrace-ag" ? "${var.vpc_name}-allow-activegate-iap-ssh" : "${local.fw_prefix}-${var.instance_prefix}-allow-iap-ssh"
  network     = var.vpc_name
  description = "Allow inbound SSH via Google Cloud Identity-Aware Proxy to ActiveGate instances"

  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"]
  target_tags   = var.network_tags

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# 6. ActiveGate GCE Virtual Machines across Availability Zones
resource "google_compute_instance" "activegate" {
  count        = local.instance_count
  project      = var.project_id
  name         = "${var.instance_prefix}-${format("%02d", count.index + 1)}"
  zone         = var.zones[count.index % length(var.zones)]
  machine_type = var.machine_type
  description  = "Dynatrace ActiveGate Node ${count.index + 1} (${var.zones[count.index % length(var.zones)]})"

  tags = var.network_tags

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 50
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = local.subnet_self_link
    network_ip = var.assign_static_ips && var.subnet_cidr != "" ? cidrhost(var.subnet_cidr, var.static_ip_start_offset + count.index) : null
    # Zero external public IP: egress routes through VPC Cloud NAT
  }

  service_account {
    email  = local.sa_email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -euxo pipefail

    echo "=========================================================="
    echo "Starting Dynatrace ActiveGate Automated Installation"
    echo "Host: $(hostname), IP: $(hostname -I)"
    echo "Date: $(date -u)"
    echo "=========================================================="

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl wget ca-certificates jq

    INSTALLER_URL="${var.dynatrace_url}/api/v1/deployment/installer/gateway/unix/latest?arch=x86"
    INSTALLER_DEST="/tmp/Dynatrace-ActiveGate-Linux-x86.sh"

    echo "Downloading ActiveGate Linux installer from Dynatrace SaaS..."
    curl -sS -L \
      -H "Authorization: Api-Token ${var.dynatrace_api_token}" \
      "$INSTALLER_URL" \
      -o "$INSTALLER_DEST"

    chmod +x "$INSTALLER_DEST"

    echo "Executing ActiveGate installation with Network Zone: ${var.network_zone}..."
    "$INSTALLER_DEST" --set-network-zone="${var.network_zone}"

    echo "Verifying ActiveGate systemd service..."
    systemctl daemon-reload
    systemctl enable dynatracegateway
    systemctl restart dynatracegateway

    echo "Checking ActiveGate status..."
    systemctl status dynatracegateway || true

    echo "ActiveGate installation sequence completed successfully."
  EOT

  metadata = {
    enable-oslogin = "TRUE"
  }

  lifecycle {
    ignore_changes = [
      metadata_startup_script,
    ]
  }

  depends_on = [
    google_compute_subnetwork.activegate_subnet,
    google_compute_firewall.activegate_ingress_9999,
  ]
}

# State migration blocks ensuring zero downtime / no resource recreation
moved {
  from = google_compute_subnetwork.activegate_subnet
  to   = google_compute_subnetwork.activegate_subnet[0]
}
moved {
  from = google_service_account.activegate_sa
  to   = google_service_account.activegate_sa[0]
}
moved {
  from = google_project_iam_member.activegate_logging
  to   = google_project_iam_member.activegate_logging[0]
}
moved {
  from = google_project_iam_member.activegate_monitoring
  to   = google_project_iam_member.activegate_monitoring[0]
}
moved {
  from = google_compute_firewall.activegate_ingress_9999
  to   = google_compute_firewall.activegate_ingress_9999[0]
}
moved {
  from = google_compute_firewall.activegate_ingress_iap
  to   = google_compute_firewall.activegate_ingress_iap[0]
}

