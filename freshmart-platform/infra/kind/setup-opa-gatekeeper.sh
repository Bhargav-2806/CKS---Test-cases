#!/usr/bin/env bash
# =============================================================================
# Phase 4.6 — OPA Gatekeeper Setup
# Installs Gatekeeper v3.17.1 + applies ConstraintTemplates + Constraints
# CKS Domain: Minimize Microservice Vulnerabilities (20%)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

GATEKEEPER_VERSION="v3.17.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/../../k8s/13-opa-gatekeeper"

# ─── Step 1: Verify cluster ───────────────────────────────────────────────────
info "Checking Kind cluster is running..."
kubectl cluster-info --context kind-freshmart-cks > /dev/null 2>&1 || \
  fail "Kind cluster 'freshmart-cks' not found. Run setup.sh first."
ok "Cluster found"

# ─── Step 2: Install Gatekeeper ───────────────────────────────────────────────
info "Installing OPA Gatekeeper $GATEKEEPER_VERSION..."

if kubectl get namespace gatekeeper-system &>/dev/null; then
  warn "gatekeeper-system namespace already exists — skipping install"
else
  kubectl apply -f \
    "https://raw.githubusercontent.com/open-policy-agent/gatekeeper/${GATEKEEPER_VERSION}/deploy/gatekeeper.yaml"
  ok "Gatekeeper manifests applied"
fi

# ─── Step 3: Wait for Gatekeeper pods ────────────────────────────────────────
info "Waiting for Gatekeeper controller-manager pods to be ready (up to 120s)..."
kubectl rollout status deployment/gatekeeper-controller-manager \
  -n gatekeeper-system --timeout=120s
ok "gatekeeper-controller-manager ready"

info "Waiting for Gatekeeper audit pod to be ready..."
kubectl rollout status deployment/gatekeeper-audit \
  -n gatekeeper-system --timeout=60s
ok "gatekeeper-audit ready"

# ─── Step 4: Apply ConstraintTemplates ───────────────────────────────────────
info "Applying ConstraintTemplates (Rego policy definitions)..."
kubectl apply -f "$K8S_DIR/templates/"
ok "ConstraintTemplates applied"

# Wait for CRDs to be established (Gatekeeper generates CRDs from templates)
info "Waiting for ConstraintTemplate CRDs to be established (15s)..."
sleep 15

# Verify CRDs are ready
for crd in k8snolatesttags k8sallowedrepos k8srequireresourcelimits \
           k8snoprivileged k8snohostpaths k8srequireseccomp k8srequirenonroots; do
  if kubectl get crd "${crd}.constraints.gatekeeper.sh" &>/dev/null; then
    ok "CRD ready: ${crd}.constraints.gatekeeper.sh"
  else
    warn "CRD not yet ready: ${crd} — will retry after constraints apply"
  fi
done

# ─── Step 5: Apply Constraints ───────────────────────────────────────────────
info "Applying Constraints (policy instances per namespace)..."
kubectl apply -f "$K8S_DIR/constraints/"
ok "Constraints applied"

# ─── Step 6: Summary ─────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Phase 4.6 — OPA Gatekeeper installed and configured"
echo "══════════════════════════════════════════════════════════"
echo ""
info "Gatekeeper pods:"
kubectl get pods -n gatekeeper-system
echo ""
info "ConstraintTemplates:"
kubectl get constrainttemplates
echo ""
info "Constraints:"
kubectl get constraints -A 2>/dev/null || kubectl get constraint 2>/dev/null || true
echo ""
echo "  Next: run manual tests to verify policies are enforced"
echo "  kubectl describe k8snolatesttag freshmart-no-latest-tag"
echo "  See PHASE-4.6-OPA-GATEKEEPER.md for the full test guide"
echo "══════════════════════════════════════════════════════════"
