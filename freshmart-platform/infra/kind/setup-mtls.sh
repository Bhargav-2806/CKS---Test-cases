#!/usr/bin/env bash
# =============================================================================
# Phase 4.9 — mTLS Setup (order-service → payment-service)
# CKS Domain: Minimize Microservice Vulnerabilities (20%)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
step()  { echo -e "\n${CYAN}══ $* ══${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/../.."
MTLS_DIR="$ROOT/k8s/15-mtls"

# ─── Step 1: Verify cluster + cert-manager ────────────────────────────────────
step "Checking prerequisites"
kubectl cluster-info --context kind-freshmart-cks > /dev/null 2>&1 || \
  fail "Kind cluster not found."
kubectl get clusterissuer freshmart-ca-issuer &>/dev/null || \
  fail "freshmart-ca-issuer not found. Run setup-cert-manager.sh first (Phase 4.8)."
ok "Cluster + cert-manager ready"

# ─── Step 2: Issue mTLS certificates ─────────────────────────────────────────
step "Creating mTLS certificates"
kubectl apply -f "$MTLS_DIR/00-certificates.yaml"

info "Waiting for payment-service server cert..."
kubectl wait certificate/payment-server-tls -n tesco-payments \
  --for=condition=Ready --timeout=60s
ok "payment-server-tls ready"

info "Waiting for order-service client cert..."
kubectl wait certificate/order-client-tls -n tesco-core \
  --for=condition=Ready --timeout=60s
ok "order-client-tls ready"

# ─── Step 3: Patch ConfigMaps ─────────────────────────────────────────────────
step "Patching ConfigMaps with mTLS env vars"
kubectl apply -f "$MTLS_DIR/01-configmap-patches.yaml"
ok "ConfigMaps patched"

# ─── Step 4: Rebuild and reload images ───────────────────────────────────────
step "Rebuilding payment-service (Go mTLS) and order-service (Python mTLS client)"
cd "$ROOT"

info "Building payment-service..."
docker build -t freshmart/payment-service:latest \
  services/payment-service/ -f services/payment-service/Dockerfile
ok "payment-service built"

info "Building order-service..."
docker build -t freshmart/order-service:latest \
  services/order-service/ -f services/order-service/Dockerfile
ok "order-service built"

info "Loading images into Kind cluster..."
kind load docker-image freshmart/payment-service:latest --name freshmart-cks
kind load docker-image freshmart/order-service:latest --name freshmart-cks
ok "Images loaded"

# ─── Step 5: Apply deployment patches (mount certs) ──────────────────────────
step "Patching deployments to mount mTLS certificates"
kubectl apply -f "$MTLS_DIR/02-deployment-patches.yaml"
ok "Deployment patches applied"

# ─── Step 6: Restart deployments to pick up new images + config ──────────────
step "Restarting deployments"
kubectl rollout restart deployment/payment-service -n tesco-payments
kubectl rollout restart deployment/order-service -n tesco-core

info "Waiting for payment-service rollout..."
kubectl rollout status deployment/payment-service -n tesco-payments --timeout=90s
ok "payment-service rolled out"

info "Waiting for order-service rollout..."
kubectl rollout status deployment/order-service -n tesco-core --timeout=90s
ok "order-service rolled out"

# ─── Step 7: Verify mTLS is active ───────────────────────────────────────────
step "Verifying mTLS"

PAYMENT_POD=$(kubectl get pod -n tesco-payments -l app=payment-service \
  -o jsonpath='{.items[0].metadata.name}')

# Check logs — should show mTLS startup message
sleep 3
if kubectl logs "$PAYMENT_POD" -n tesco-payments 2>/dev/null | \
    grep -q "listening with mTLS"; then
  ok "payment-service confirmed running with mTLS"
else
  warn "Could not confirm mTLS from logs — check manually:"
  info "kubectl logs $PAYMENT_POD -n tesco-payments | grep mTLS"
fi

# Check cert files are mounted
if kubectl exec "$PAYMENT_POD" -n tesco-payments -- \
    ls /certs/tls.crt /certs/tls.key /certs/ca.crt &>/dev/null 2>&1; then
  ok "mTLS cert files mounted at /certs/"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Phase 4.9 — mTLS COMPLETE"
echo "══════════════════════════════════════════════════════════════"
echo ""
info "Certificates:"
kubectl get certificate -n tesco-payments
kubectl get certificate -n tesco-core
echo ""
echo "  Test mTLS handshake:"
echo "  kubectl exec -n tesco-core deploy/order-service -- \\"
echo "    openssl s_client -connect payment-service.tesco-payments.svc.cluster.local:8004 \\"
echo "    -cert /certs/tls.crt -key /certs/tls.key -CAfile /certs/ca.crt"
echo ""
echo "  See PHASE-4.9-MTLS.md for full test guide"
echo "══════════════════════════════════════════════════════════════"
