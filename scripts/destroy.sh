#!/bin/bash
# ============================================================
# DESTROY SCRIPT - Full Teardown
# ============================================================
#
# This script tears down ALL resources in reverse order:
#   1. PSC resources (NEG, Service Attachment)
#   2. Kubernetes workloads (Flask, Nginx)
#   3. Terraform infrastructure (GKE, LBs, VPCs, etc.)
#
# Usage:
#   cd Commit-mission
#   ./scripts/destroy.sh          # Interactive
#   ./scripts/destroy.sh -y       # Auto-approve
#
# ============================================================
set -euo pipefail

AUTO_APPROVE=""
if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
  AUTO_APPROVE="-auto-approve"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$ROOT_DIR/terraform"
K8S_DIR="$ROOT_DIR/k8s-manifests"

echo "============================================"
echo "  Tearing Down All Resources"
echo "============================================"
echo ""

# Read Terraform outputs
cd "$TF_DIR"
PROJECT_A=$(terraform output -raw project_a 2>/dev/null || echo "")
PROJECT_B=$(terraform output -raw project_b 2>/dev/null || echo "")
REGION=$(terraform output -raw region 2>/dev/null || echo "us-central1")
ZONE=$(terraform output -raw zone 2>/dev/null || echo "us-central1-a")

if [[ -z "$PROJECT_A" || -z "$PROJECT_B" ]]; then
  echo "ERROR: Could not read project IDs from Terraform state."
  echo "Make sure you're in the correct directory and Terraform state exists."
  exit 1
fi

echo "  Project A: $PROJECT_A"
echo "  Project B: $PROJECT_B"
echo ""

# ============================================================
# STEP 1: Remove PSC Resources
# ============================================================
echo "=== Step 1/3: Removing PSC Resources ==="

# Detach PSC NEG from External LB backend
echo "  Detaching PSC NEG from backend service..."
gcloud compute backend-services remove-backend external-lb-backend \
  --global \
  --project="$PROJECT_A" \
  --network-endpoint-group=psc-neg-a \
  --network-endpoint-group-region="$REGION" --quiet 2>/dev/null || true

# Delete PSC NEG
echo "  Deleting PSC NEG..."
gcloud compute network-endpoint-groups delete psc-neg-a \
  --region="$REGION" \
  --project="$PROJECT_A" --quiet 2>/dev/null || true

# Delete PSC Service Attachment
echo "  Deleting PSC Service Attachment..."
gcloud compute service-attachments delete psc-service-b \
  --region="$REGION" \
  --project="$PROJECT_B" --quiet 2>/dev/null || true

echo ""

# ============================================================
# STEP 2: Remove Kubernetes Resources
# ============================================================
echo "=== Step 2/3: Removing Kubernetes Resources ==="

# Get GKE credentials (might fail if cluster is already gone)
gcloud container clusters get-credentials gke-cluster-b \
  --zone "$ZONE" \
  --project "$PROJECT_B" 2>/dev/null || true

# Delete Flask app
echo "  Deleting Flask application..."
kubectl delete -f "$K8S_DIR/flask-app.yaml" 2>/dev/null || true

# Delete Nginx internal service override
echo "  Deleting Nginx internal service..."
kubectl delete -f "$K8S_DIR/nginx-internal-svc.yaml" 2>/dev/null || true

# Delete Nginx Ingress Controller
echo "  Deleting Nginx Ingress Controller..."
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/cloud/deploy.yaml 2>/dev/null || true

# Wait for K8s to clean up LB resources
echo "  Waiting for Kubernetes LB cleanup (30s)..."
sleep 30

echo ""

# ============================================================
# STEP 3: Terraform Destroy
# ============================================================
echo "=== Step 3/3: Destroying GCP Infrastructure ==="
cd "$TF_DIR"
terraform destroy $AUTO_APPROVE

echo ""
echo "============================================"
echo "  TEARDOWN COMPLETE!"
echo "============================================"
echo "  All resources have been destroyed."
echo "  Only the 'default' VPC remains in each project (no cost)."
echo "============================================"
