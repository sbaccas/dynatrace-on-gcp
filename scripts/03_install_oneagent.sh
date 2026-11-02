#!/usr/bin/env bash
# ==============================================================================
# 03_install_oneagent.sh - Install Dynatrace OneAgent on Workload VM
# ==============================================================================
# Supports both:
# 1. Remote installation via gcloud IAP SSH (default from operator workstation)
# 2. Local execution on the target Linux host (--local)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RED="\033[0;31m"
RESET="\033[0m"

ENV_FILE="${ROOT_DIR}/bootstrap/bootstrap.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

PROJECT="${WORKLOAD_PROJECT_ID:-workload-app-prod}"
ZONE="${TARGET_WORKLOAD_ZONE:-us-central1-a}"
VM_NAME="${TARGET_WORKLOAD_VM:-workload-vm-01}"
NETWORK_ZONE="${ACTIVEGATE_NETWORK_ZONE:-workload-prod}"
DT_URL="${DYNATRACE_URL:-}"
DT_TOKEN="${DYNATRACE_API_TOKEN:-}"
RUN_LOCAL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local)
            RUN_LOCAL=true
            shift
            ;;
        --project)
            PROJECT="$2"
            shift 2
            ;;
        --zone)
            ZONE="$2"
            shift 2
            ;;
        --vm)
            VM_NAME="$2"
            shift 2
            ;;
        --network-zone)
            NETWORK_ZONE="$2"
            shift 2
            ;;
        --token)
            DT_TOKEN="$2"
            shift 2
            ;;
        --url)
            DT_URL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$DT_TOKEN" ]]; then
    echo -e "${RED}[ERROR] Dynatrace API token is required. Pass via --token or set DYNATRACE_API_TOKEN.${RESET}"
    exit 1
fi

echo -e "\n${BOLD}${CYAN}======================================================${RESET}"
echo -e "${BOLD}${CYAN}  Step 3: Dynatrace OneAgent Workload Deployment      ${RESET}"
echo -e "${BOLD}${CYAN}======================================================${RESET}\n"

install_local() {
    echo -e "${YELLOW}--> [LOCAL] Downloading Dynatrace OneAgent installer...${RESET}"
    curl -s -S -L -o /tmp/Dynatrace-OneAgent-Linux.sh \
        -H "Authorization: Api-Token ${DT_TOKEN}" \
        "${DT_URL}/api/v1/deployment/installer/agent/unix/default/latest?arch=x86&flavor=default"

    echo -e "${YELLOW}--> [LOCAL] Installing OneAgent with network zone '${NETWORK_ZONE}'...${RESET}"
    sudo /bin/sh /tmp/Dynatrace-OneAgent-Linux.sh \
        --set-monitoring-mode=fullstack \
        --set-network-zone="${NETWORK_ZONE}"

    rm -f /tmp/Dynatrace-OneAgent-Linux.sh
    echo -e "${GREEN}[OK] Local OneAgent installation finished.${RESET}"

    echo -e "${YELLOW}--> Verifying configuration...${RESET}"
    sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --get-network-zone
    sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --get-server
}

if [[ "$RUN_LOCAL" == "true" ]]; then
    install_local
else
    echo -e "${CYAN}Target Project:${RESET} ${BOLD}${PROJECT}${RESET}"
    echo -e "${CYAN}Target Zone:${RESET}    ${BOLD}${ZONE}${RESET}"
    echo -e "${CYAN}Target VM:${RESET}      ${BOLD}${VM_NAME}${RESET}"
    echo -e "${CYAN}Network Zone:${RESET}   ${BOLD}${NETWORK_ZONE}${RESET}\n"

    echo -e "${YELLOW}--> Testing IAP SSH connectivity to ${VM_NAME}...${RESET}"
    gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT" --tunnel-through-iap --command="hostname; uptime"

    echo -e "\n${YELLOW}--> Executing remote OneAgent installation on ${VM_NAME}...${RESET}"
    REMOTE_SCRIPT="
set -euo pipefail
echo '--> Downloading OneAgent installer...'
curl -s -S -L -o /tmp/Dynatrace-OneAgent-Linux.sh \
    -H 'Authorization: Api-Token ${DT_TOKEN}' \
    '${DT_URL}/api/v1/deployment/installer/agent/unix/default/latest?arch=x86&flavor=default'

echo '--> Running OneAgent installer...'
sudo /bin/sh /tmp/Dynatrace-OneAgent-Linux.sh \
    --set-monitoring-mode=fullstack \
    --set-network-zone='${NETWORK_ZONE}'

rm -f /tmp/Dynatrace-OneAgent-Linux.sh
echo '--> Checking oneagentctl...'
sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --get-network-zone
sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --get-server
"
    gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT" --tunnel-through-iap --command="$REMOTE_SCRIPT"

    echo -e "\n${BOLD}${GREEN}======================================================${RESET}"
    echo -e "${BOLD}${GREEN}  OneAgent Deployed Successfully on ${VM_NAME}!      ${RESET}"
    echo -e "${BOLD}${GREEN}======================================================${RESET}\n"
fi
