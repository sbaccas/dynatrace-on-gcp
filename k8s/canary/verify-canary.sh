#!/usr/bin/env bash
# ==============================================================================
# Helper Script: Deploy & Verify Canary Diagnostic Workload
# ==============================================================================
set -euo pipefail

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RESET="\033[0m"

echo -e "${BOLD}${YELLOW}--> Deploying Canary Diagnostic Workload to GKE...${RESET}"
kubectl apply -f "$(dirname "$0")/canary-deployment.yaml"

echo -e "${BOLD}${YELLOW}--> Waiting for Canary Pods to become Ready...${RESET}"
kubectl -n dynatrace-canary rollout status deployment/canary-diagnostic --timeout=120s

echo -e "\n${BOLD}${GREEN}--> Inspecting Canary Diagnostic Logs:${RESET}"
kubectl -n dynatrace-canary logs -l app=canary-diagnostic --prefix --tail=10
