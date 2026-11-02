#!/usr/bin/env bash
# ==============================================================================
# 01_deploy_terraform.sh - Provision Observability Platform & ActiveGate Cluster
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/environments/prod"

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RED="\033[0;31m"
RESET="\033[0m"

AUTO_APPROVE=false
for arg in "$@"; do
    case "$arg" in
        -y|--auto-approve)
            AUTO_APPROVE=true
            ;;
    esac
done

echo -e "\n${BOLD}${CYAN}======================================================${RESET}"
echo -e "${BOLD}${CYAN}  Step 1: Terraform Infrastructure Deployment         ${RESET}"
echo -e "${BOLD}${CYAN}======================================================${RESET}\n"

if [[ ! -d "$TF_DIR" ]]; then
    echo -e "${RED}[ERROR] Terraform directory '${TF_DIR}' does not exist.${RESET}"
    exit 1
fi

if [[ ! -f "${TF_DIR}/backend.tf" ]] || [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
    echo -e "${RED}[ERROR] backend.tf or terraform.tfvars missing in ${TF_DIR}.${RESET}"
    echo -e "Please run './scripts/00_bootstrap.sh' first to generate configuration."
    exit 1
fi

echo -e "${YELLOW}--> Initializing Terraform backend in: ${TF_DIR}${RESET}"
cd "$TF_DIR"
terraform init -reconfigure

echo -e "\n${YELLOW}--> Generating Terraform execution plan...${RESET}"
terraform plan -out=tfplan

if [[ "$AUTO_APPROVE" != "true" ]]; then
    echo -e "\n${BOLD}${YELLOW}Do you want to apply this Terraform execution plan? (yes/no): ${RESET}"
    read -r CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo -e "${RED}[ABORTED] Terraform apply cancelled by user.${RESET}"
        rm -f tfplan
        exit 0
    fi
fi

echo -e "\n${YELLOW}--> Applying Terraform configuration...${RESET}"
terraform apply -auto-approve tfplan
rm -f tfplan

echo -e "\n${BOLD}${GREEN}======================================================${RESET}"
echo -e "${BOLD}${GREEN}  Terraform Outputs                                   ${RESET}"
echo -e "${BOLD}${GREEN}======================================================${RESET}\n"
terraform output

echo -e "\n${BOLD}${GREEN}[OK] Step 1 Complete: Infrastructure provisioned successfully.${RESET}\n"
