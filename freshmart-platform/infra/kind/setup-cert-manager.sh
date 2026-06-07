#!/usr/bin/env bash
# =============================================================================
# Phase 4.8 — cert-manager + TLS Ingress Setup
# CKS Domain: Cluster Setup (10%) — Ingress with TLS
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
step()  { echo -e "\n${CYAN}══ $* ══${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/../../k8s/14-cert-manager"
CERT_MANAGER_VERSION="v1.16.2"

# ─── Step 1: Verify cluster ───────────────────────────────────────────────────
step "Checking Kind cluster"
kubectl cluster-info --context kind-freshmart-cks > /dev/null 2>&1 || \
  fail "Kind cluster 'freshmart-cks' not found."
ok "Cluster found"

# ─── Step 2: Install cert-manager ────────────────────────────────────────────
step "Installing cert-manager $CERT_MANAGER_VERSION"
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update jetstack

if helm status cert-manager -n cert-manager &>/dev/null; then
  info "cert-manager already installed — skipping"
else
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version "$CERT_MANAGER_VERSION" \
    --set crds.enabled=true \
    --set global.leaderElection.namespace=cert-manager \
    --wait \
    --timeout=120s
  ok "cert-manager installed"
fi

# ─── Step 3: Wait for cert-manager webhook ───────────────────────────────────
step "Waiting for cert-manager webhook to be ready"
kubectl rollout status deployment/cert-manager-webhook \
  -n cert-manager --timeout=60s
# Extra wait — webhook needs a few seconds to register after rollout
sleep 10
ok "cert-manager webhook ready"

# ─── Step 4: Apply ClusterIssuers ────────────────────────────────────────────
step "Creating ClusterIssuers (self-signed bootstrapper + FreshMart CA)"
kubectl apply -f "$K8S_DIR/00-clusterissuers.yaml"

# Wait for CA cert to be issued
info "Waiting for FreshMart CA certificate to be ready..."
kubectl wait certificate/freshmart-ca \
  -n cert-manager \
  --for=condition=Ready \
  --timeout=60s
ok "FreshMart CA certificate issued"

# ─── Step 5: Apply TLS Certificates ──────────────────────────────────────────
step "Creating TLS Certificates for freshmart.local"
kubectl apply -f "$K8S_DIR/01-certificates.yaml"

info "Waiting for tesco-frontend TLS certificate..."
kubectl wait certificate/freshmart-tls \
  -n tesco-frontend \
  --for=condition=Ready \
  --timeout=60s
ok "freshmart-tls ready in tesco-frontend"

info "Waiting for tesco-core TLS certificate..."
kubectl wait certificate/freshmart-api-tls \
  -n tesco-core \
  --for=condition=Ready \
  --timeout=60s
ok "freshmart-api-tls ready in tesco-core"

# ─── Step 6: Apply TLS Ingresses ─────────────────────────────────────────────
step "Patching Ingresses with TLS + security headers"
kubectl apply -f "$K8S_DIR/02-ingress-tls.yaml"
ok "Ingresses updated with TLS"

# ─── Step 7: Add /etc/hosts entry ────────────────────────────────────────────
step "Checking /etc/hosts for freshmart.local"
if grep -q "freshmart.local" /etc/hosts; then
  ok "freshmart.local already in /etc/hosts"
else
  warn "Add this line to /etc/hosts (requires sudo):"
  echo ""
  echo "  sudo sh -c 'echo \"127.0.0.1 freshmart.local\" >> /etc/hosts'"
  echo ""
fi

# ─── Step 8: Summary ─────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Phase 4.8 — cert-manager + TLS COMPLETE"
echo "══════════════════════════════════════════════════════════════"
echo ""
info "cert-manager pods:"
kubectl get pods -n cert-manager
echo ""
info "Certificate status:"
kubectl get certificate -A
echo ""
info "TLS secrets created:"
kubectl get secret freshmart-tls -n tesco-frontend -o \
  jsonpath='{.metadata.name}{" → expires: "}{.metadata.annotations.cert-manager\.io/certificate-expiry-time}{"\n"}' 2>/dev/null || \
  kubectl get secret freshmart-tls -n tesco-frontend 2>/dev/null
echo ""
echo "  Test HTTPS (after adding freshmart.local to /etc/hosts):"
echo "  curl -k https://freshmart.local/api/products"
echo "  curl -k https://freshmart.local"
echo ""
echo "  Or in browser: https://freshmart.local"
echo "  (accept self-signed cert warning)"
echo ""
echo "  See PHASE-4.8-CERT-MANAGER-TLS.md for full test guide"
echo "══════════════════════════════════════════════════════════════"
