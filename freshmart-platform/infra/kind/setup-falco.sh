#!/usr/bin/env bash
# =============================================================================
# Phase 4.7 — Falco Runtime Security Setup
# Installs Falco via Helm with modern_ebpf driver + FreshMart custom rules
# CKS Domain: Monitoring, Logging & Runtime Security (20%)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
step()  { echo -e "\n${CYAN}══ $* ══${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FALCO_VALUES="$SCRIPT_DIR/../../security/falco/falco-values.yaml"
FALCO_RULES="$SCRIPT_DIR/../../security/falco/rules/freshmart-rules.yaml"
FALCO_NAMESPACE="falco"
FALCO_CHART_VERSION="4.8.1"

# ─── Step 1: Verify cluster ───────────────────────────────────────────────────
step "Checking Kind cluster"
kubectl cluster-info --context kind-freshmart-cks > /dev/null 2>&1 || \
  fail "Kind cluster 'freshmart-cks' not found. Run setup.sh first."
ok "Cluster found"

# ─── Step 2: Check kernel version (modern_ebpf needs >= 5.8) ─────────────────
step "Checking kernel version"
KERNEL=$(docker exec freshmart-cks-control-plane uname -r 2>/dev/null || echo "unknown")
info "Kernel version: $KERNEL"
KERNEL_MAJOR=$(echo "$KERNEL" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL" | cut -d. -f2)
if [ "$KERNEL_MAJOR" -gt 5 ] || { [ "$KERNEL_MAJOR" -eq 5 ] && [ "$KERNEL_MINOR" -ge 8 ]; }; then
  ok "Kernel $KERNEL supports modern_ebpf (>= 5.8)"
else
  warn "Kernel $KERNEL may not support modern_ebpf. Will try ebpf fallback."
fi

# ─── Step 3: Add Falco Helm repo ─────────────────────────────────────────────
step "Adding falcosecurity Helm repo"
helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
helm repo update falcosecurity
ok "falcosecurity repo ready"

# ─── Step 4: Create namespace ────────────────────────────────────────────────
step "Creating $FALCO_NAMESPACE namespace"
kubectl create namespace "$FALCO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Label as privileged — Falco needs host PID and elevated syscall access
kubectl label namespace "$FALCO_NAMESPACE" \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite
ok "Namespace $FALCO_NAMESPACE ready (PSA: privileged)"

# ─── Step 5: Install Falco ───────────────────────────────────────────────────
step "Installing Falco $FALCO_CHART_VERSION"

if helm status falco -n "$FALCO_NAMESPACE" &>/dev/null; then
  info "Falco already installed — upgrading..."
  HELM_CMD="upgrade"
else
  HELM_CMD="install"
fi

helm "$HELM_CMD" falco falcosecurity/falco \
  --namespace "$FALCO_NAMESPACE" \
  --version "$FALCO_CHART_VERSION" \
  --values "$FALCO_VALUES" \
  --set-file "customRules.freshmart_rules\\.yaml=$FALCO_RULES" \
  --set driver.kind=modern_ebpf \
  --set falco.json_output=true \
  --set falco.log_level=info \
  --set "tolerations[0].key=node-role.kubernetes.io/control-plane" \
  --set "tolerations[0].operator=Exists" \
  --set "tolerations[0].effect=NoSchedule" \
  --wait \
  --timeout=180s || {
    warn "modern_ebpf failed. Retrying with ebpf driver..."
    helm "$HELM_CMD" falco falcosecurity/falco \
      --namespace "$FALCO_NAMESPACE" \
      --version "$FALCO_CHART_VERSION" \
      --values "$FALCO_VALUES" \
      --set-file "customRules.freshmart_rules\\.yaml=$FALCO_RULES" \
      --set driver.kind=ebpf \
      --set falco.json_output=true \
      --wait \
      --timeout=180s
  }

ok "Falco installed"

# ─── Step 6: Wait for DaemonSet ──────────────────────────────────────────────
step "Waiting for Falco DaemonSet to be ready"
kubectl rollout status daemonset/falco -n "$FALCO_NAMESPACE" --timeout=120s
ok "Falco DaemonSet ready"

# ─── Step 7: Verify custom rules loaded ──────────────────────────────────────
step "Verifying FreshMart custom rules loaded"
sleep 5
FALCO_POD=$(kubectl get pods -n "$FALCO_NAMESPACE" -l app.kubernetes.io/name=falco \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if kubectl exec -n "$FALCO_NAMESPACE" "$FALCO_POD" -- \
    falco --list 2>/dev/null | grep -q "FreshMart"; then
  ok "FreshMart rules loaded and recognised by Falco"
else
  warn "Could not verify rules via falco --list (may still be loading). Check logs:"
  info "kubectl logs -n $FALCO_NAMESPACE $FALCO_POD | head -30"
fi

# ─── Step 8: Summary ─────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Phase 4.7 — Falco Runtime Security INSTALLED"
echo "══════════════════════════════════════════════════════════════"
echo ""
info "Falco pods (DaemonSet — one per node):"
kubectl get pods -n "$FALCO_NAMESPACE" -o wide
echo ""
echo "  Watch live alerts:"
echo "  kubectl logs -n falco -l app.kubernetes.io/name=falco -f | grep -i freshmart"
echo ""
echo "  Trigger a test alert (shell in container):"
echo "  kubectl exec -it \$(kubectl get pod -n tesco-core -l app=product-service"
echo "    -o jsonpath='{.items[0].metadata.name}') -n tesco-core -- /bin/sh"
echo ""
echo "  See PHASE-4.7-FALCO.md for the full test guide"
echo "══════════════════════════════════════════════════════════════"
