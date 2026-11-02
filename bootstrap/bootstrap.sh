#!/usr/bin/env bash
# ==============================================================================
# Dynatrace Observability Platform - Bootstrap Script
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

ENV_FILE="${1:-${SCRIPT_DIR}/bootstrap.env}"

if [[ -f "$ENV_FILE" ]]; then
    echo -e "${YELLOW}--> Loading configuration from: ${ENV_FILE}${RESET}"
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
else
    echo -e "${RED}[ERROR] Configuration file '${ENV_FILE}' not found!${RESET}"
    exit 1
fi

echo -e "\n${BOLD}${CYAN}======================================================${RESET}"
echo -e "${BOLD}${CYAN}  Dynatrace Observability Platform - Bootstrap        ${RESET}"
echo -e "${BOLD}${CYAN}======================================================${RESET}\n"

echo -e "${CYAN}Organization ID:${RESET}      ${BOLD}${GCP_ORG_ID:-N/A}${RESET}"
echo -e "${CYAN}Observability Folder:${RESET} ${BOLD}${OBSERVABILITY_FOLDER_ID:-N/A}${RESET}"
echo -e "${CYAN}Control Project ID:${RESET}   ${BOLD}${GCP_CONTROL_PROJECT_ID}${RESET}"
echo -e "${CYAN}Platform Project ID:${RESET}  ${BOLD}${GCP_PLATFORM_PROJECT_ID}${RESET}"
echo -e "${CYAN}Target Region:${RESET}        ${BOLD}${GCP_REGION}${RESET}"
echo -e "${CYAN}State Bucket:${RESET}         ${BOLD}${TF_STATE_BUCKET}${RESET}\n"

# 1. Check / Create Control Project
echo -e "${YELLOW}--> Checking control project '${GCP_CONTROL_PROJECT_ID}'...${RESET}"
if gcloud projects describe "$GCP_CONTROL_PROJECT_ID" >/dev/null 2>&1; then
    echo -e "${GREEN}[OK] Control project ${GCP_CONTROL_PROJECT_ID} exists.${RESET}"
else
    echo -e "    Creating project ${BOLD}${GCP_CONTROL_PROJECT_ID}${RESET} in Folder ${OBSERVABILITY_FOLDER_ID}..."
    gcloud projects create "$GCP_CONTROL_PROJECT_ID" \
        --folder="$OBSERVABILITY_FOLDER_ID" \
        --name="Dynatrace Control Prod"
    echo -e "${GREEN}[OK] Project ${GCP_CONTROL_PROJECT_ID} created.${RESET}"

    if [[ -n "${BILLING_ACCOUNT_ID:-}" ]]; then
        echo -e "    Linking billing account ${BILLING_ACCOUNT_ID}..."
        gcloud billing projects link "$GCP_CONTROL_PROJECT_ID" --billing-account="$BILLING_ACCOUNT_ID"
        echo -e "${GREEN}[OK] Billing account linked.${RESET}"
    fi
fi

# 2. Enable Control Project APIs
echo -e "\n${YELLOW}--> Enabling required APIs on ${GCP_CONTROL_PROJECT_ID}...${RESET}"
gcloud services enable storage.googleapis.com cloudresourcemanager.googleapis.com --project="$GCP_CONTROL_PROJECT_ID" --quiet
echo -e "${GREEN}[OK] Control APIs enabled.${RESET}"

# 3. Check / Create Platform Project
echo -e "\n${YELLOW}--> Checking platform infrastructure project '${GCP_PLATFORM_PROJECT_ID}'...${RESET}"
if gcloud projects describe "$GCP_PLATFORM_PROJECT_ID" >/dev/null 2>&1; then
    echo -e "${GREEN}[OK] Platform project ${GCP_PLATFORM_PROJECT_ID} exists.${RESET}"
else
    echo -e "    Creating project ${BOLD}${GCP_PLATFORM_PROJECT_ID}${RESET} in Folder ${OBSERVABILITY_FOLDER_ID}..."
    gcloud projects create "$GCP_PLATFORM_PROJECT_ID" \
        --folder="$OBSERVABILITY_FOLDER_ID" \
        --name="Dynatrace Platform Prod"
    echo -e "${GREEN}[OK] Project ${GCP_PLATFORM_PROJECT_ID} created.${RESET}"

    if [[ -n "${BILLING_ACCOUNT_ID:-}" ]]; then
        echo -e "    Linking billing account ${BILLING_ACCOUNT_ID}..."
        gcloud billing projects link "$GCP_PLATFORM_PROJECT_ID" --billing-account="$BILLING_ACCOUNT_ID"
        echo -e "${GREEN}[OK] Billing account linked.${RESET}"
    fi
fi

# 4. Enable Platform APIs
echo -e "\n${YELLOW}--> Enabling required platform APIs on ${GCP_PLATFORM_PROJECT_ID}...${RESET}"
REQUIRED_PLATFORM_APIS=(
    "compute.googleapis.com"
    "container.googleapis.com"
    "monitoring.googleapis.com"
    "logging.googleapis.com"
    "pubsub.googleapis.com"
    "iam.googleapis.com"
    "artifactregistry.googleapis.com"
    "cloudresourcemanager.googleapis.com"
)
for api in "${REQUIRED_PLATFORM_APIS[@]}"; do
    echo -e "    Enabling ${BOLD}${api}${RESET}..."
    gcloud services enable "$api" --project="$GCP_PLATFORM_PROJECT_ID" --quiet
done
echo -e "${GREEN}[OK] Platform APIs enabled.${RESET}"

# 5. Check / Create Scoping Projects Folder & Dedicated Scoping Project
echo -e "\n${YELLOW}--> Checking Scoping Projects folder...${RESET}"
if [[ -n "${SCOPING_PROJECTS_FOLDER_ID:-}" ]] && gcloud resource-manager folders describe "$SCOPING_PROJECTS_FOLDER_ID" >/dev/null 2>&1; then
    echo -e "${GREEN}[OK] Scoping Projects folder ${SCOPING_PROJECTS_FOLDER_ID} exists.${RESET}"
else
    echo -e "    Creating folder '${SCOPING_PROJECTS_FOLDER_NAME:-Scoping Projects}' under folder ${OBSERVABILITY_FOLDER_ID}..."
    FOLDER_OUT=$(gcloud resource-manager folders create \
        --display-name="${SCOPING_PROJECTS_FOLDER_NAME:-Scoping Projects}" \
        --folder="${OBSERVABILITY_FOLDER_ID}" \
        --format="value(name)")
    SCOPING_PROJECTS_FOLDER_ID="${FOLDER_OUT#folders/}"
    echo -e "${GREEN}[OK] Folder created: folders/${SCOPING_PROJECTS_FOLDER_ID}${RESET}"
fi

if [[ -n "${GCP_SCOPING_PROJECT_ID:-}" ]]; then
    echo -e "\n${YELLOW}--> Checking dedicated empty Scoping Project '${GCP_SCOPING_PROJECT_ID}'...${RESET}"
    if gcloud projects describe "$GCP_SCOPING_PROJECT_ID" >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] Scoping project ${GCP_SCOPING_PROJECT_ID} exists.${RESET}"
    else
        echo -e "    Creating empty scoping project ${BOLD}${GCP_SCOPING_PROJECT_ID}${RESET} in Folder ${SCOPING_PROJECTS_FOLDER_ID}..."
        gcloud projects create "$GCP_SCOPING_PROJECT_ID" \
            --folder="$SCOPING_PROJECTS_FOLDER_ID" \
            --name="Dynatrace Scoping Project 01"
        echo -e "${GREEN}[OK] Project ${GCP_SCOPING_PROJECT_ID} created.${RESET}"

        if [[ -n "${BILLING_ACCOUNT_ID:-}" ]]; then
            echo -e "    Linking billing account ${BILLING_ACCOUNT_ID}..."
            gcloud billing projects link "$GCP_SCOPING_PROJECT_ID" --billing-account="$BILLING_ACCOUNT_ID"
            echo -e "${GREEN}[OK] Billing account linked.${RESET}"
        fi
    fi

    echo -e "\n${YELLOW}--> Enabling Cloud Monitoring API on ${GCP_SCOPING_PROJECT_ID}...${RESET}"
    gcloud services enable monitoring.googleapis.com --project="$GCP_SCOPING_PROJECT_ID" --quiet
    echo -e "${GREEN}[OK] Monitoring API enabled on scoping project.${RESET}"
fi

# 6. Check / Create GCS State Bucket in Control Project
echo -e "\n${YELLOW}--> Checking GCS state bucket 'gs://${TF_STATE_BUCKET}' in ${GCP_CONTROL_PROJECT_ID}...${RESET}"
if gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" >/dev/null 2>&1; then
    echo -e "${GREEN}[OK] Bucket gs://${TF_STATE_BUCKET} exists.${RESET}"
else
    echo -e "    Creating bucket ${BOLD}gs://${TF_STATE_BUCKET}${RESET} in region ${GCP_REGION}..."
    gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
        --project="$GCP_CONTROL_PROJECT_ID" \
        --location="$GCP_REGION" \
        --uniform-bucket-level-access
    gcloud storage buckets update "gs://${TF_STATE_BUCKET}" --versioning
    echo -e "${GREEN}[OK] Bucket gs://${TF_STATE_BUCKET} created with object versioning enabled.${RESET}"
fi

# 7. Generate backend.tf & terraform.tfvars
BACKEND_TF_PATH="${ROOT_DIR}/terraform/environments/prod/backend.tf"
cat <<BACKEND_EOF > "$BACKEND_TF_PATH"
# Automatically generated by bootstrap.sh from bootstrap/bootstrap.env
# Generated on: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# DO NOT EDIT MANUALLY

terraform {
  backend "gcs" {
    bucket = "${TF_STATE_BUCKET}"
    prefix = "${TF_STATE_PREFIX}"
  }
}
BACKEND_EOF
echo -e "${GREEN}[OK] Written: ${BACKEND_TF_PATH}${RESET}"

TFVARS_PATH="${ROOT_DIR}/terraform/environments/prod/terraform.tfvars"
cat <<TFVARS_EOF > "$TFVARS_PATH"
# Automatically generated by bootstrap.sh from bootstrap/bootstrap.env
# Generated on: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# DO NOT EDIT MANUALLY

project_id              = "${GCP_PLATFORM_PROJECT_ID}"
region                  = "${GCP_REGION}"
zone                    = "${GCP_ZONE}"
cluster_name            = "${GKE_CLUSTER_NAME}"
machine_type            = "${GKE_MACHINE_TYPE}"
scoping_project_id      = "${GCP_SCOPING_PROJECT_ID}"
monitored_project_ids   = ${MONITORED_PROJECT_IDS:-["${GCP_PLATFORM_PROJECT_ID}", "workload-app-prod"]}
workload_project_id     = "${WORKLOAD_PROJECT_ID:-workload-app-prod}"
workload_vpc_name       = "${ACTIVEGATE_VPC_NAME:-workload-vpc}"
activegate_zones        = ${ACTIVEGATE_ZONES:-["${GCP_ZONE}"]}
activegate_subnet_name  = "${ACTIVEGATE_SUBNET_NAME:-workload-activegate-subnet}"
activegate_subnet_cidr  = "${ACTIVEGATE_SUBNET_CIDR:-10.10.2.0/24}"
activegate_source_cidrs = ${ACTIVEGATE_SOURCE_CIDRS:-["10.10.0.0/24", "10.10.2.0/24"]}
dynatrace_url           = "${DYNATRACE_URL:-}"
dynatrace_api_token     = "${DYNATRACE_API_TOKEN:-}"
activegate_network_zone = "${ACTIVEGATE_NETWORK_ZONE:-workload-prod}"
TFVARS_EOF
echo -e "${GREEN}[OK] Written: ${TFVARS_PATH}${RESET}"

echo -e "\n${BOLD}${GREEN}======================================================${RESET}"
echo -e "${BOLD}${GREEN}  Bootstrap Execution Finished Successfully!          ${RESET}"
echo -e "${BOLD}${GREEN}======================================================${RESET}\n"

