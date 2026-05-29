#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

# shellcheck disable=SC1091
source "$(dirname "$PROJECT_ROOT")/shared/scripts/load-deploy-phase-timing.sh" "$PROJECT_ROOT" 2>/dev/null \
  || source "$HOME/Documents/Github/shared/scripts/load-deploy-phase-timing.sh" "$PROJECT_ROOT" \
  || { echo "Error: deploy timing library not found" >&2; exit 1; }
deploy_timing_init "database-server"

SERVICE_NAME="database-server"
# In-cluster stack: two Deployments (see k8s/in-cluster-databases.yaml)
DB_DEPLOYMENTS=(db-server-postgres db-server-redis)
NAMESPACE="${NAMESPACE:-statex-apps}"
K8S_DIR="$PROJECT_ROOT/k8s"

preflight_service_health() {
  echo -e "${YELLOW}Preflight: checking Kubernetes and current service health...${NC}"

  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}Namespace not found: $NAMESPACE${NC}"
    exit 1
  fi

  if ! kubectl get nodes >/dev/null 2>&1; then
    echo -e "${RED}kubectl cannot reach cluster${NC}"
    exit 1
  fi

  BAD_PODS=$(kubectl get pods -n "$NAMESPACE" -l 'app in (db-server-postgres,db-server-redis)' --no-headers 2>/dev/null | awk '$3 ~ /Error|CrashLoopBackOff|ImagePullBackOff|CreateContainerConfigError|CreateContainerError|ErrImagePull/ {print $1}')
  if [ -n "$BAD_PODS" ]; then
    echo -e "${YELLOW}Unhealthy DB pods detected (deploy will attempt recovery):${NC}"
    kubectl get pods -n "$NAMESPACE" -l 'app in (db-server-postgres,db-server-redis)' -o wide || true
    for pod in $BAD_PODS; do
      echo -e "${YELLOW}--- describe pod/$pod ---${NC}"
      kubectl describe pod -n "$NAMESPACE" "$pod" || true
      echo -e "${YELLOW}--- logs pod/$pod (tail 80) ---${NC}"
      kubectl logs -n "$NAMESPACE" "$pod" --tail=80 2>/dev/null || kubectl logs -n "$NAMESPACE" "$pod" -c postgres --tail=80 2>/dev/null || kubectl logs -n "$NAMESPACE" "$pod" -c redis --tail=80 2>/dev/null || true
    done
    if [ "${DATABASE_DEPLOY_PREFLIGHT_STRICT:-0}" = "1" ]; then
      echo -e "${RED}DATABASE_DEPLOY_PREFLIGHT_STRICT=1: aborting.${NC}"
      exit 1
    fi
  fi

  echo -e "${GREEN}Preflight passed (cluster reachable)${NC}"
}


echo -e "${BLUE}==========================================================${NC}"
echo -e "${BLUE}  Database Server - Kubernetes Deployment${NC}"
echo -e "${BLUE}==========================================================${NC}"

if [ ! -d "$K8S_DIR" ]; then
  echo -e "${RED}Missing k8s directory: $K8S_DIR${NC}"
  exit 1
fi

deploy_timing_run_phase "Preflight" preflight_service_health

deploy_timing_phase_start "Apply Kubernetes manifests"
echo -e "${YELLOW}Applying Kubernetes manifests...${NC}"
for manifest in configmap.yaml external-secret.yaml in-cluster-databases.yaml deployment.yaml service.yaml ingress.yaml; do
  if [ -f "$K8S_DIR/$manifest" ]; then
    kubectl apply -f "$K8S_DIR/$manifest" -n "$NAMESPACE"
  fi
done
echo -e "${GREEN}OK Kubernetes manifests applied${NC}"
deploy_timing_phase_end "Apply Kubernetes manifests"

deploy_timing_phase_start "Rollout restart"
echo -e "${YELLOW}Triggering rollout restart...${NC}"
for dep in "${DB_DEPLOYMENTS[@]}"; do
  if kubectl get deployment "$dep" -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl rollout restart deployment/"$dep" -n "$NAMESPACE"
  else
    echo -e "${YELLOW}Skip: deployment/$dep not found (apply manifests first)${NC}"
  fi
done
echo -e "${GREEN}OK Rollout restart triggered${NC}"
deploy_timing_phase_end "Rollout restart"

deploy_timing_phase_start "Wait for rollout"
echo -e "${YELLOW}Waiting for rollout...${NC}"
for dep in "${DB_DEPLOYMENTS[@]}"; do
  if kubectl get deployment "$dep" -n "$NAMESPACE" >/dev/null 2>&1; then
    deploy_timing_k8s_rollout_wait kubectl "$dep" "$NAMESPACE" "120s" "app=$dep"
  fi
done
echo -e "${GREEN}OK Rollout complete${NC}"
deploy_timing_phase_end "Wait for rollout"

deploy_timing_phase_start "Post-deploy status"
echo -e "${YELLOW}Current pods:${NC}"
kubectl get pods -n "$NAMESPACE" -l 'app in (db-server-postgres,db-server-redis)'
deploy_timing_phase_end "Post-deploy status"

deploy_timing_finish_success "Database Server"
DEPLOY_TIMING_FINISHED=1
exit 0
