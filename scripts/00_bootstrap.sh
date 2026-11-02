#!/usr/bin/env bash
# ==============================================================================
# 00_bootstrap.sh - Initialize GCP Projects, Folders, GCS State Bucket, and IAM
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

echo -e "\n${BOLD}${CYAN}======================================================${RESET}"
echo -e "${BOLD}${CYAN}  Step 0: GCP Foundation & Bootstrap                  ${RESET}"
echo -e "${BOLD}${CYAN}======================================================${RESET}\n"

# Verify CLI prerequisites
for cmd in gcloud terraform kubectl helm jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}[ERROR] Required command '$cmd' is not installed or not in PATH.${RESET}"
        exit 1
    fi
done
echo -e "${GREEN}[OK] All prerequisite CLI tools are present.${RESET}"

# Verify active gcloud authentication
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || true)
if [[ -z "$ACTIVE_ACCOUNT" ]]; then
    echo -e "${RED}[ERROR] No active gcloud account found. Run: gcloud auth login${RESET}"
    exit 1
fi
echo -e "${GREEN}[OK] Active GCP account: ${BOLD}${ACTIVE_ACCOUNT}${RESET}"

ENV_FILE="${1:-${ROOT_DIR}/bootstrap/bootstrap.env}"
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}[ERROR] Configuration file '${ENV_FILE}' not found!${RESET}"
    echo -e "Please copy or create ${ROOT_DIR}/bootstrap/bootstrap.env before proceeding."
    exit 1
fi

echo -e "\n${YELLOW}--> Executing foundational bootstrap...${RESET}"
bash "${ROOT_DIR}/bootstrap/bootstrap.sh" "$ENV_FILE"

echo -e "\n${BOLD}${GREEN}======================================================${RESET}"
echo -e "${BOLD}${GREEN}  Step 0 Complete: Environment Ready for Terraform    ${RESET}"
echo -e "${BOLD}${GREEN}======================================================${RESET}\n"
