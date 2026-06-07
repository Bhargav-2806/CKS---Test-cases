#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# FreshMart CKS — Phase 3 Bootstrap Script
# Runs from: freshmart-platform/
# Usage:  chmod +x infra/kind/setup.sh && ./infra/kind/setup.sh
# Tear down: kind delete cluster --name freshmart-cks
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CLUSTER_NAME="freshmart-cks"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─── Prerequisites ────────────────────────────────────────────────────────────
log "Checking prerequisites..."
for cmd in kind kubectl docker; do
  command -v "$cmd" &>/dev/null || die "$cmd not found. Please install it first."
done
ok "All prerequisites found"

# ─── Create Kind Cluster ──────────────────────────────────────────────────────
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  warn "Cluster '${CLUSTER_NAME}' already exists — skipping creation"
else
  log "Creating Kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "$CLUSTER_NAME" --config "$SCRIPT_DIR/cluster.yaml"
  ok "Cluster created"
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

# ─── Build Docker Images ──────────────────────────────────────────────────────
log "Building Docker images..."

docker build -t freshmart/product-service:latest \
  "$ROOT_DIR/services/product-service"
ok "product-service built"

docker build -t freshmart/cart-service:latest \
  "$ROOT_DIR/services/cart-service"
ok "cart-service built"

docker build -t freshmart/order-service:latest \
  "$ROOT_DIR/services/order-service"
ok "order-service built"

docker build -t freshmart/payment-service:latest \
  "$ROOT_DIR/services/payment-service"
ok "payment-service built"

# Frontend: bake in the ingress URL (localhost port 80, routed by nginx ingress)
docker build -t freshmart/frontend:latest \
  --build-arg NEXT_PUBLIC_PRODUCT_SERVICE_URL=http://localhost \
  --build-arg NEXT_PUBLIC_CART_SERVICE_URL=http://localhost \
  --build-arg NEXT_PUBLIC_ORDER_SERVICE_URL=http://localhost \
  "$ROOT_DIR/services/frontend"
ok "frontend built"

# ─── Load Images into Kind ────────────────────────────────────────────────────
log "Loading images into Kind cluster..."
for img in \
  freshmart/product-service:latest \
  freshmart/cart-service:latest \
  freshmart/order-service:latest \
  freshmart/payment-service:latest \
  freshmart/frontend:latest; do
  kind load docker-image "$img" --name "$CLUSTER_NAME"
  ok "$img loaded"
done

# ─── Install ingress-nginx (Kind-specific) ────────────────────────────────────
log "Installing ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/kind/deploy.yaml

log "Waiting for ingress-nginx controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
ok "ingress-nginx ready"

# ─── Apply K8s Manifests ──────────────────────────────────────────────────────
K8S="$ROOT_DIR/k8s"

log "Applying namespaces..."
kubectl apply -f "$K8S/00-namespaces.yaml"

log "Applying RBAC..."
kubectl apply -f "$K8S/01-rbac.yaml"

log "Applying secrets..."
kubectl apply -f "$K8S/02-secrets.yaml"

log "Applying configmaps..."
kubectl apply -f "$K8S/03-configmaps.yaml"

# Create init.sql ConfigMap from file (idempotent)
kubectl create configmap postgresql-init \
  --namespace tesco-data \
  --from-file=01-init.sql="$ROOT_DIR/infra/db/init.sql" \
  --dry-run=client -o yaml | kubectl apply -f -
ok "postgresql-init ConfigMap applied"

log "Applying storage (PostgreSQL + Kafka)..."
kubectl apply -f "$K8S/04-storage/"

log "Waiting for PostgreSQL to be ready..."
kubectl rollout status statefulset/postgresql -n tesco-data --timeout=120s
ok "PostgreSQL ready"

log "Waiting for Kafka to be ready (KRaft startup takes ~60s)..."
kubectl rollout status statefulset/kafka -n tesco-messaging --timeout=180s
ok "Kafka ready"

log "Applying Deployments..."
kubectl apply -f "$K8S/05-deployments/"

log "Applying Ingress..."
kubectl apply -f "$K8S/06-ingress/"

log "Applying NetworkPolicies..."
kubectl apply -f "$K8S/07-network-policies/"

# ─── Wait for all Deployments ─────────────────────────────────────────────────
log "Waiting for all Deployments to be ready..."
for deploy_ns in \
  "product-service tesco-core" \
  "cart-service    tesco-core" \
  "order-service   tesco-core" \
  "payment-service tesco-payments" \
  "frontend        tesco-frontend"; do
  name=$(echo "$deploy_ns" | awk '{print $1}')
  ns=$(echo "$deploy_ns"   | awk '{print $2}')
  kubectl rollout status deployment/"$name" -n "$ns" --timeout=180s
  ok "$name ready"
done

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  FreshMart CKS Cluster — Phase 3 Complete!       ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo "  Frontend:        http://localhost"
echo "  Product API:     http://localhost/api/products"
echo "  Cart API:        http://localhost/api/cart/{session}"
echo "  Order API:       http://localhost/api/orders"
echo ""
echo "  View all pods:   kubectl get pods -A"
echo "  View services:   kubectl get svc -A"
echo "  Tear down:       kind delete cluster --name $CLUSTER_NAME"
echo ""
