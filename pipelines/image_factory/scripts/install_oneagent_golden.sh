#!/usr/bin/env bash
# ==============================================================================
# install_oneagent_golden.sh - Pre-install OneAgent in Staged Golden Image Mode
# ==============================================================================
set -euo pipefail

echo "=========================================================="
echo "Starting Golden Image Dynatrace OneAgent Staged Installation"
echo "=========================================================="

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get install -y curl wget ca-certificates jq

echo "==> Downloading OneAgent Linux installer from Dynatrace SaaS..."
curl -sS -L \
  -H "Authorization: Api-Token ${DT_TOKEN}" \
  "${DT_URL}/api/v1/deployment/installer/agent/unix/default/latest?arch=x86&flavor=default" \
  -o /tmp/Dynatrace-OneAgent-Linux.sh

echo "==> Installing OneAgent in non-configured staging mode..."
# PRESERVE_INSTALLER=0 ensures the 276MB binary installer is cleaned up
sudo /bin/sh /tmp/Dynatrace-OneAgent-Linux.sh \
  --set-monitoring-mode=fullstack \
  --set-network-zone=DEFAULT \
  --set-host-group=gcp-workloads \
  PRESERVE_INSTALLER=0

echo "==> Stopping OneAgent service before disk capture..."
sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --shutdown || true
sudo systemctl stop oneagent || true
sudo systemctl disable oneagent || true # Prevent start before network-zone is bound

echo "==> Clearing instance-specific IDs to prevent duplicate host reporting..."
sudo rm -f /var/lib/dynatrace/oneagent/agent/config/runtime.conf
sudo rm -f /var/lib/dynatrace/oneagent/agent/config/original_endpoints.conf
sudo rm -f /var/lib/dynatrace/oneagent/agent/config/ruxitagentconnection.conf
sudo rm -rf /var/log/dynatrace/oneagent/*

echo "==> Dynatrace Golden Image Staged Installation Finished Successfully."
