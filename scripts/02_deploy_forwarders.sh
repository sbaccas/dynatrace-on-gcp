#!/usr/bin/env bash
# ==============================================================================
# 02_deploy_forwarders.sh - Deploy Dynatrace GKE Metric & Log Forwarders
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

ENV_FILE="${1:-${ROOT_DIR}/bootstrap/bootstrap.env}"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

GCP_PROJECT="${GCP_PLATFORM_PROJECT_ID:-dynatrace-platform-prod}"
SCOPING_PROJECT="${GCP_SCOPING_PROJECT_ID:-dynatrace-scope-01-prod}"
PUBSUB_SUB="${PUBSUB_SUBSCRIPTION_NAME:-dynatrace-gcp-logs-sub}"
GKE_CLUSTER="${GKE_CLUSTER_NAME:-dynatrace-forwarder-gke}"
GKE_ZONE="${GCP_ZONE:-us-central1-a}"
DYNATRACE_URL="${DYNATRACE_URL:-}"
DYNATRACE_API_TOKEN="${DYNATRACE_API_TOKEN:-}"
NAMESPACE="dynatrace"

echo -e "\n${BOLD}${CYAN}======================================================${RESET}"
echo -e "${BOLD}${CYAN}  Step 2: Deploy Dynatrace GKE Forwarders             ${RESET}"
echo -e "${BOLD}${CYAN}======================================================${RESET}\n"

if [[ -z "$DYNATRACE_URL" ]] || [[ -z "$DYNATRACE_API_TOKEN" ]]; then
    echo -e "${RED}[ERROR] DYNATRACE_URL and DYNATRACE_API_TOKEN must be set in ${ENV_FILE} or exported.${RESET}"
    exit 1
fi

echo -e "${YELLOW}--> Obtaining credentials for GKE cluster '${GKE_CLUSTER}' in ${GKE_ZONE}...${RESET}"
gcloud container clusters get-credentials "$GKE_CLUSTER" --zone="$GKE_ZONE" --project="$GCP_PROJECT"
echo -e "${GREEN}[OK] Connected to GKE cluster.${RESET}"

echo -e "\n${YELLOW}--> Ensuring namespace '${NAMESPACE}' exists...${RESET}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}[OK] Namespace '${NAMESPACE}' ready.${RESET}"

echo -e "\n${YELLOW}--> Configuring Kubernetes secret for Dynatrace API token...${RESET}"
kubectl create secret generic dynatrace-gcp-monitor-secret \
    --namespace="$NAMESPACE" \
    --from-literal=dynatrace-access-key="$DYNATRACE_API_TOKEN" \
    --from-literal=api-token="$DYNATRACE_API_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}[OK] Kubernetes secret configured.${RESET}"

echo -e "\n${YELLOW}--> Deploying/Upgrading Dynatrace Log Forwarder (Helm)...${RESET}"
helm upgrade --install dynatrace-gcp-logs "${ROOT_DIR}/helm/dynatrace-gcp-monitor" \
    --namespace="$NAMESPACE" \
    --values "${ROOT_DIR}/helm/values/values-logs.yaml" \
    --set gcpProjectId="$GCP_PROJECT" \
    --set logsSubscriptionProject="$GCP_PROJECT" \
    --set logsSubscriptionId="$PUBSUB_SUB" \
    --set gcpServiceAccount="dt-log-forwarder@${GCP_PROJECT}.iam.gserviceaccount.com" \
    --set dynatraceUrl="$DYNATRACE_URL" \
    --set dynatraceAccessKey="$DYNATRACE_API_TOKEN"
echo -e "${GREEN}[OK] Log Forwarder Helm release deployed.${RESET}"

echo -e "\n${YELLOW}--> Deploying/Upgrading Dynatrace Metric Forwarder (Helm)...${RESET}"
helm upgrade --install dynatrace-gcp-metrics "${ROOT_DIR}/helm/dynatrace-gcp-monitor" \
    --namespace="$NAMESPACE" \
    --values "${ROOT_DIR}/helm/values/values-metrics.yaml" \
    --set gcpProjectId="$SCOPING_PROJECT" \
    --set gcpServiceAccount="dt-metric-forwarder@${GCP_PROJECT}.iam.gserviceaccount.com" \
    --set dynatraceUrl="$DYNATRACE_URL" \
    --set dynatraceAccessKey="$DYNATRACE_API_TOKEN"
echo -e "${GREEN}[OK] Metric Forwarder Helm release deployed.${RESET}"

echo -e "\n${YELLOW}--> Waiting for forwarder pods to reach Ready status...${RESET}"
kubectl -n "$NAMESPACE" rollout status deployment/dynatrace-gcp-logs --timeout=120s
kubectl -n "$NAMESPACE" rollout status deployment/dynatrace-gcp-metrics --timeout=120s

echo -e "\n${BOLD}${GREEN}======================================================${RESET}"
echo -e "${BOLD}${GREEN}  Dynatrace Forwarders Deployed Successfully!         ${RESET}"
echo -e "${BOLD}${GREEN}======================================================${RESET}\n"
kubectl -n "$NAMESPACE" get pods -l 'app in (dynatrace-gcp-logs, dynatrace-gcp-metrics)'
