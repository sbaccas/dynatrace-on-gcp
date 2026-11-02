# ==============================================================================
# HashiCorp Packer Template: Dynatrace Pre-Baked Golden Image
# ==============================================================================
# Builds a hardened Ubuntu 22.04 LTS Compute Engine image with OneAgent
# pre-installed in staging template mode.
# ==============================================================================

packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.4"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "project_id" {
  type    = string
  default = "shared-images-prod"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "dynatrace_url" {
  type    = string
  default = "https://<your-environment-id>.live.dynatrace.com"
}

variable "dynatrace_token" {
  type      = string
  sensitive = true
}

source "googlecompute" "ubuntu_golden" {
  project_id            = var.project_id
  zone                  = var.zone
  source_image_family   = "ubuntu-2204-lts"
  image_name            = "gold-ubuntu-2204-dynatrace-{{timestamp}}"
  image_family          = "gold-ubuntu-2204-dynatrace"
  image_description     = "Enterprise Golden Image with Dynatrace OneAgent pre-baked in staging mode"
  ssh_username          = "packer"
  machine_type          = "e2-standard-4"
  disk_size             = 50
  disk_type             = "pd-balanced"
  use_internal_ip       = true
  omit_external_ip      = true
  subnetwork            = "projects/${var.project_id}/regions/us-central1/subnetworks/image-builder-subnet"
}

build {
  sources = ["source.googlecompute.ubuntu_golden"]

  provisioner "shell" {
    environment_vars = [
      "DT_URL=${var.dynatrace_url}",
      "DT_TOKEN=${var.dynatrace_token}"
    ]
    script = "${path.root}/scripts/install_oneagent_golden.sh"
  }

  provisioner "file" {
    source      = "${path.root}/scripts/dynatrace-zone-init.sh"
    destination = "/tmp/dynatrace-zone-init.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/dynatrace-zone-init.sh /usr/local/bin/dynatrace-zone-init.sh",
      "sudo chmod +x /usr/local/bin/dynatrace-zone-init.sh",
      "echo 'Configuring systemd first-boot network zone activation service...'",
      "sudo tee /etc/systemd/system/dynatrace-zone-init.service > /dev/null <<'EOF'",
      "[Unit]",
      "Description=Dynatrace OneAgent Dynamic Network Zone Initialization",
      "After=network-online.target google-guest-agent.service",
      "Wants=network-online.target",
      "",
      "[Service]",
      "Type=oneshot",
      "ExecStart=/usr/local/bin/dynatrace-zone-init.sh",
      "RemainAfterExit=yes",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "sudo systemctl enable dynatrace-zone-init.service"
    ]
  }
}
