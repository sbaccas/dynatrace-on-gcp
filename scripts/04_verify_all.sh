#!/usr/bin/env bash
# ==============================================================================
# 04_verify_all.sh - Automated End-to-End Dynatrace GCP Verification Suite
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

PLATFORM_PROJECT="${GCP_PLATFORM_PROJECT_ID:-dynatrace-platform-prod}"
GKE_CLUSTER="${GKE_CLUSTER_NAME:-dynatrace-forwarder-gke}"
GKE_ZONE="${GCP_ZONE:-us-central1-a}"
WORKLOAD_PROJECT="${WORKLOAD_PROJECT_ID:-workload-app-prod}"
WORKLOAD_VM="${TARGET_WORKLOAD_VM:-workload-vm-01}"
WORKLOAD_ZONE="${TARGET_WORKLOAD_ZONE:-us-central1-a}"
DT_URL="${DYNATRACE_URL:-}"
DT_TOKEN="${DYNATRACE_API_TOKEN:-}"

echo -e "\n${BOLD}${CYAN}======================================================${RESET}"
echo -e "${BOLD}${CYAN}  Step 4: Dynatrace GCP End-to-End Verification       ${RESET}"
echo -e "${BOLD}${CYAN}======================================================${RESET}\n"

PASS_COUNT=0
FAIL_COUNT=0

record_result() {
    local name="$1"
    local status="$2"
    local details="$3"
    if [[ "$status" == "PASS" ]]; then
        echo -e "${GREEN}[PASS] ${BOLD}${name}${RESET} - ${details}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}[FAIL] ${BOLD}${name}${RESET} - ${details}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# 1. GKE Credentials & Pods
echo -e "${YELLOW}--> 1. Checking GKE Forwarder Pods...${RESET}"
if gcloud container clusters get-credentials "$GKE_CLUSTER" --zone="$GKE_ZONE" --project="$PLATFORM_PROJECT" >/dev/null 2>&1; then
    METRICS_POD_STATUS=$(kubectl -n dynatrace get pods -l app=dynatrace-gcp-metrics -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
    LOGS_POD_STATUS=$(kubectl -n dynatrace get pods -l app=dynatrace-gcp-logs -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")

    if [[ "$METRICS_POD_STATUS" == "Running" ]]; then
        record_result "GKE Metric Forwarder Pod" "PASS" "Pod is Running"
    else
        record_result "GKE Metric Forwarder Pod" "FAIL" "Pod status: ${METRICS_POD_STATUS}"
    fi

    if [[ "$LOGS_POD_STATUS" == "Running" ]]; then
        record_result "GKE Log Forwarder Pod" "PASS" "Pod is Running"
    else
        record_result "GKE Log Forwarder Pod" "FAIL" "Pod status: ${LOGS_POD_STATUS}"
    fi
else
    record_result "GKE Cluster Connection" "FAIL" "Failed to authenticate to ${GKE_CLUSTER}"
fi

# 2. Metric Ingestion Telemetry
echo -e "\n${YELLOW}--> 2. Checking Metric Ingestion Telemetry...${RESET}"
METRIC_LOG=$(kubectl -n dynatrace logs -l app=dynatrace-gcp-metrics --tail=40 2>/dev/null || true)
if echo "$METRIC_LOG" | grep -q "'linesOk':"; then
    LINES_OK=$(echo "$METRIC_LOG" | grep -o "'linesOk': [0-9]*" | head -n 1)
    record_result "Metric Ingest to Dynatrace" "PASS" "Active ingestion verified (${LINES_OK})"
else
    record_result "Metric Ingest to Dynatrace" "FAIL" "No 'linesOk' found in recent pod logs"
fi

# 3. Log Ingestion Telemetry
echo -e "\n${YELLOW}--> 3. Checking Log Ingestion Telemetry...${RESET}"
LOG_OUTPUT=$(kubectl -n dynatrace logs -l app=dynatrace-gcp-logs --tail=40 2>/dev/null || true)
if echo "$LOG_OUTPUT" | grep -q "Dynatrace connectivity: Ok"; then
    record_result "Log Ingest to Dynatrace" "PASS" "Dynatrace connectivity reported Ok"
else
    record_result "Log Ingest to Dynatrace" "FAIL" "Did not find successful log delivery confirmation"
fi

# 4. Dynatrace ActiveGates API
echo -e "\n${YELLOW}--> 4. Checking Dynatrace ActiveGates API...${RESET}"
if [[ -n "$DT_TOKEN" ]]; then
    AG_RESPONSE=$(curl -s -H "Authorization: Api-Token ${DT_TOKEN}" "${DT_URL}/api/v2/activeGates" || true)
    AG_COUNT=$(echo "$AG_RESPONSE" | jq '.activeGates | length' 2>/dev/null || echo 0)
    if [[ "$AG_COUNT" -ge 2 ]]; then
        record_result "ActiveGate Cluster Nodes" "PASS" "Found ${AG_COUNT} active gates connected to tenant"
    else
        record_result "ActiveGate Cluster Nodes" "FAIL" "Expected at least 2 active gates, found ${AG_COUNT}"
    fi
else
    record_result "ActiveGate Cluster Nodes" "FAIL" "DT_TOKEN not set"
fi

# 5. Dynatrace OneAgent Host Entities API
echo -e "\n${YELLOW}--> 5. Checking Dynatrace Monitored Host Entities...${RESET}"
if [[ -n "$DT_TOKEN" ]]; then
    HOST_RESPONSE=$(curl -s -H "Authorization: Api-Token ${DT_TOKEN}" "${DT_URL}/api/v2/entities?entitySelector=type(%22HOST%22)" || true)
    HOST_COUNT=$(echo "$HOST_RESPONSE" | jq '.totalCount' 2>/dev/null || echo 0)
    if [[ "$HOST_COUNT" -ge 1 ]]; then
        HOST_NAME=$(echo "$HOST_RESPONSE" | jq -r '.entities[0].displayName' 2>/dev/null || echo "")
        record_result "OneAgent Host Entity Discovery" "PASS" "Host discovered: ${HOST_NAME}"
    else
        record_result "OneAgent Host Entity Discovery" "FAIL" "No host entities found in Dynatrace"
    fi
else
    record_result "OneAgent Host Entity Discovery" "FAIL" "DT_TOKEN not set"
fi

# 6. Workload VM -> ActiveGate Port 9999 Connectivity
echo -e "\n${YELLOW}--> 6. Checking Workload Network Connectivity to ActiveGates (:9999)...${RESET}"
CONN_CHECK=$(gcloud compute ssh "$WORKLOAD_VM" --zone="$WORKLOAD_ZONE" --project="$WORKLOAD_PROJECT" --tunnel-through-iap \
    --command="nc -zv -w 5 10.10.2.10 9999 && nc -zv -w 5 10.10.2.11 9999" 2>&1 || true)
if echo "$CONN_CHECK" | grep -q "succeeded"; then
    record_result "In-VPC ActiveGate Port 9999 Routing" "PASS" "TCP 9999 reachable across availability zones"
else
    record_result "In-VPC ActiveGate Port 9999 Routing" "FAIL" "Port 9999 connection failed or timed out"
fi

# Summary
echo -e "\n${BOLD}${CYAN}======================================================${RESET}"
echo -e "${BOLD}${CYAN}  Verification Summary: ${GREEN}${PASS_COUNT} Passed${RESET}, ${RED}${FAIL_COUNT} Failed${RESET}"
echo -e "${BOLD}${CYAN}======================================================${RESET}\n"

if [[ "$FAIL_COUNT" -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}[SUCCESS] All Dynatrace GCP platform components are operational!${RESET}\n"
    exit 0
else
    echo -e "${BOLD}${RED}[WARNING] Some components reported issues. Check logs above.${RESET}\n"
    exit 1
fi
