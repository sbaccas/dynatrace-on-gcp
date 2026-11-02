#!/usr/bin/env bash
# ==============================================================================
# dynatrace-zone-init.sh - Dynamic First-Boot Network Zone Binding Hook
# ==============================================================================
# Executed once on VM launch to dynamically bind the pre-baked OneAgent
# to the local VPC's regional ActiveGate cluster via GCP Instance Metadata.
# ==============================================================================
set -euo pipefail

echo "=========================================================="
echo "Dynatrace OneAgent Dynamic Network Zone Initialization"
echo "=========================================================="

# 1. Attempt to read network-zone attribute from GCP instance metadata
NETWORK_ZONE=$(curl -s -f -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/network-zone" 2>/dev/null || true)

# 2. Fallback to reading VPC name or default zone
if [[ -z "$NETWORK_ZONE" ]]; then
  echo "Metadata attribute 'network-zone' not found. Falling back to subnet discovery..."
  SUBNET_PATH=$(curl -s -f -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/network" 2>/dev/null || true)
  VPC_NAME=$(basename "${SUBNET_PATH:-default}")
  NETWORK_ZONE="${VPC_NAME}-prod"
fi

echo "Discovered target Dynatrace Network Zone: ${NETWORK_ZONE}"

# 3. Configure Network Zone and activate OneAgent
sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --set-network-zone="${NETWORK_ZONE}"
sudo systemctl enable oneagent
sudo systemctl restart oneagent

echo "OneAgent successfully initialized in network zone '${NETWORK_ZONE}'."
