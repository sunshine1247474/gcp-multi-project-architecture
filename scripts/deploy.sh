#!/bin/bash
# ============================================================
# DEPLOY SCRIPT - Full End-to-End Deployment
# ============================================================
#
# This script deploys the COMPLETE architecture:
#   1. Terraform  -> VPCs, subnets, firewall, NAT, GKE, External LB, Cloud Armor
#   2. Kubernetes -> Nginx Ingress Controller + Flask app
#   3. PSC        -> Service Attachment + NEG (wires Project A to Project B)
#
# Prerequisites:
#   - gcloud CLI authenticated (gcloud auth login)
#   - terraform installed
#   - kubectl installed
#   - terraform.tfvars configured with project IDs
#
# Usage:
#   cd Commit-mission
#   ./scripts/deploy.sh          # Interactive (confirms before apply)
#   ./scripts/deploy.sh -y       # Auto-approve (for CI/CD)
#
# ============================================================
set -euo pipefail

# --- Parse flags ---
AUTO_APPROVE=""
if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
  AUTO_APPROVE="-auto-approve"
fi

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$ROOT_DIR/terraform"
K8S_DIR="$ROOT_DIR/k8s-manifests"

echo "============================================"
echo "  GCP Multi-Project Architecture Deployment"
echo "============================================"
echo ""

# --- Check prerequisites ---
echo "Checking prerequisites..."
for cmd in gcloud terraform kubectl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is not installed. Please install it first."
    exit 1
  fi
done

# Check terraform.tfvars exists
if [[ ! -f "$TF_DIR/terraform.tfvars" ]]; then
  echo "ERROR: terraform.tfvars not found!"
  echo "  cp $TF_DIR/terraform.tfvars.example $TF_DIR/terraform.tfvars"
  echo "  Then edit it with your GCP project IDs."
  exit 1
fi

echo "All prerequisites met."
echo ""

# ============================================================
# STEP 1: Terraform - Deploy GCP Infrastructure
# ============================================================
echo "============================================"
echo "  Step 1/7: Deploying GCP Infrastructure"
echo "============================================"
cd "$TF_DIR"
terraform init
terraform apply $AUTO_APPROVE

# Read outputs from Terraform
PROJECT_A=$(terraform output -raw project_a)
PROJECT_B=$(terraform output -raw project_b)
REGION=$(terraform output -raw region)
ZONE=$(terraform output -raw zone)
EXTERNAL_IP=$(terraform output -raw external_lb_ip)

echo ""
echo "  Project A: $PROJECT_A"
echo "  Project B: $PROJECT_B"
echo "  External IP: $EXTERNAL_IP"
echo ""

# ============================================================
# STEP 2: Configure kubectl for GKE
# ============================================================
echo "============================================"
echo "  Step 2/7: Configuring kubectl"
echo "============================================"
gcloud container clusters get-credentials gke-cluster-b \
  --zone "$ZONE" \
  --project "$PROJECT_B"

echo "kubectl configured for gke-cluster-b"
echo ""

# ============================================================
# STEP 3: Deploy Nginx Ingress Controller
# ============================================================
echo "============================================"
echo "  Step 3/7: Deploying Nginx Ingress Controller"
echo "============================================"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/cloud/deploy.yaml

echo "Waiting for Nginx Ingress Controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo "Nginx Ingress Controller is running."
echo ""

# ============================================================
# STEP 4: Override Nginx Service to Internal Load Balancer
# ============================================================
echo "============================================"
echo "  Step 4/7: Creating Internal Load Balancer"
echo "============================================"
kubectl apply -f "$K8S_DIR/nginx-internal-svc.yaml"

echo "Waiting for Internal LB IP assignment..."
INTERNAL_IP=""
for i in $(seq 1 60); do
  INTERNAL_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "$INTERNAL_IP" ]]; then
    echo "  Internal LB IP: $INTERNAL_IP"
    break
  fi
  echo "  Waiting... ($i/60)"
  sleep 10
done

if [[ -z "$INTERNAL_IP" ]]; then
  echo "ERROR: Internal LB IP not assigned after 10 minutes"
  exit 1
fi
echo ""

# ============================================================
# STEP 5: Create PSC (Private Service Connect)
# ============================================================
echo "============================================"
echo "  Step 5/7: Setting up Private Service Connect"
echo "============================================"

# Find the Internal LB forwarding rule by its IP
FR_NAME=$(gcloud compute forwarding-rules list \
  --project="$PROJECT_B" \
  --regions="$REGION" \
  --filter="IPAddress=$INTERNAL_IP" \
  --format="value(name)")

echo "  Internal LB Forwarding Rule: $FR_NAME"

# Enable global access (required for PSC to work across projects)
echo "  Enabling global access on forwarding rule..."
gcloud compute forwarding-rules update "$FR_NAME" \
  --region="$REGION" \
  --project="$PROJECT_B" \
  --allow-global-access

# Create PSC Service Attachment (producer side - Project B)
echo "  Creating PSC Service Attachment..."
if ! gcloud compute service-attachments describe psc-service-b \
  --region="$REGION" --project="$PROJECT_B" &>/dev/null; then
  gcloud compute service-attachments create psc-service-b \
    --region="$REGION" \
    --project="$PROJECT_B" \
    --producer-forwarding-rule="$FR_NAME" \
    --connection-preference=ACCEPT_AUTOMATIC \
    --nat-subnets=psc-subnet-b
else
  echo "  (already exists)"
fi

# Create PSC NEG (consumer side - Project A)
echo "  Creating PSC Network Endpoint Group..."
if ! gcloud compute network-endpoint-groups describe psc-neg-a \
  --region="$REGION" --project="$PROJECT_A" &>/dev/null; then
  gcloud compute network-endpoint-groups create psc-neg-a \
    --region="$REGION" \
    --project="$PROJECT_A" \
    --network-endpoint-type=PRIVATE_SERVICE_CONNECT \
    --psc-target-service="projects/$PROJECT_B/regions/$REGION/serviceAttachments/psc-service-b"
else
  echo "  (already exists)"
fi

echo ""

# ============================================================
# STEP 6: Wire PSC NEG to External Load Balancer
# ============================================================
echo "============================================"
echo "  Step 6/7: Connecting PSC to External LB"
echo "============================================"

# Add PSC NEG as backend to the External LB backend service
echo "  Adding PSC NEG backend..."
gcloud compute backend-services add-backend external-lb-backend \
  --global \
  --project="$PROJECT_A" \
  --network-endpoint-group=psc-neg-a \
  --network-endpoint-group-region="$REGION" 2>/dev/null || echo "  (backend already attached)"

echo ""

# ============================================================
# STEP 7: Deploy Flask Application
# ============================================================
echo "============================================"
echo "  Step 7/7: Deploying Flask Application"
echo "============================================"
kubectl apply -f "$K8S_DIR/flask-app.yaml"

echo "Waiting for Flask pods to be ready..."
kubectl wait --for=condition=ready pod \
  --selector=app=flask-hello \
  --timeout=120s

echo ""
echo "============================================"
echo "  DEPLOYMENT COMPLETE!"
echo "============================================"
echo ""
echo "  Architecture:"
echo "  External User"
echo "       |"
echo "       v"
echo "  Cloud Armor (WAF/DDoS protection)"
echo "       |"
echo "       v"
echo "  External LB: http://$EXTERNAL_IP"
echo "       |"
echo "       v (via Private Service Connect)"
echo "  Internal LB: $INTERNAL_IP (Project B)"
echo "       |"
echo "       v"
echo "  GKE Cluster -> Nginx Ingress -> Flask App"
echo ""
echo "  Test command:"
echo "    curl http://$EXTERNAL_IP"
echo ""
echo "  NOTE: It may take 5-10 minutes for health checks"
echo "  to pass and traffic to flow end-to-end."
echo "============================================"
