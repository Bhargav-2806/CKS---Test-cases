#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# FreshMart — Phase 4.3 RBAC Audit Script
# Checks all kube-bench 5.1.x items + CKS RBAC best practices
#
# Usage:
#   chmod +x infra/kind/rbac-audit.sh
#   ./infra/kind/rbac-audit.sh
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0; WARN=0

pass() { echo -e "  ${GREEN}✅ PASS${NC}  $*"; ((PASS++)); }
fail() { echo -e "  ${RED}❌ FAIL${NC}  $*"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}⚠️  WARN${NC}  $*"; ((WARN++)); }
info() { echo -e "  ${BLUE}ℹ️  INFO${NC}  $*"; }
section() { echo ""; echo -e "${BLUE}── $* ──────────────────────────────────${NC}"; }

echo ""
echo "════════════════════════════════════════════════════"
echo "  FreshMart Phase 4.3 — RBAC Audit"
echo "  kube-bench: 5.1.1 → 5.1.13"
echo "════════════════════════════════════════════════════"

# ─────────────────────────────────────────────────────────────────────────────
section "5.1.1 — cluster-admin bindings"
# ─────────────────────────────────────────────────────────────────────────────

echo "  All ClusterRoleBindings to cluster-admin:"
CLUSTER_ADMIN_BINDINGS=$(kubectl get clusterrolebindings \
  -o jsonpath='{range .items[?(@.roleRef.name=="cluster-admin")]}{.metadata.name}{"\t"}{range .subjects[*]}{.kind}:{.name}{" "}{end}{"\n"}{end}')

if [ -z "$CLUSTER_ADMIN_BINDINGS" ]; then
  pass "No cluster-admin ClusterRoleBindings found"
else
  while IFS= read -r line; do
    BINDING_NAME=$(echo "$line" | awk '{print $1}')
    SUBJECTS=$(echo "$line" | cut -f2-)
    # System bindings are expected — flag any non-system ones
    if echo "$BINDING_NAME" | grep -qE "^(kubeadm|system:|cluster-admin)"; then
      info "System binding (expected): $BINDING_NAME → $SUBJECTS"
    else
      fail "Non-system cluster-admin binding: $BINDING_NAME → $SUBJECTS"
    fi
  done <<< "$CLUSTER_ADMIN_BINDINGS"
  # If only system bindings, still pass
  NON_SYSTEM=$(echo "$CLUSTER_ADMIN_BINDINGS" | grep -vE "^(kubeadm|system:|cluster-admin)" | wc -l | tr -d ' ')
  [ "$NON_SYSTEM" -eq 0 ] && pass "No non-system cluster-admin bindings"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "5.1.2 — Minimize access to Secrets"
# ─────────────────────────────────────────────────────────────────────────────

WILDCARD_SECRET_ROLES=$(kubectl get roles,clusterroles -A -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
problems = []
for item in data.get('items', []):
    ns = item.get('metadata', {}).get('namespace', 'cluster')
    name = item.get('metadata', {}).get('name', '')
    if name.startswith('system:'): continue
    for rule in item.get('rules', []):
        resources = rule.get('resources', [])
        verbs = rule.get('verbs', [])
        if ('secrets' in resources or '*' in resources) and \
           any(v in verbs for v in ['get', 'list', 'watch', '*']):
            problems.append(f'{ns}/{name}: secrets access with verbs={verbs}')
for p in problems:
    print(p)
" 2>/dev/null)

if [ -z "$WILDCARD_SECRET_ROLES" ]; then
  pass "No non-system roles with broad secrets access"
else
  while IFS= read -r line; do
    warn "Role has secrets access: $line"
  done <<< "$WILDCARD_SECRET_ROLES"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "5.1.3 — No wildcard [*] in Roles or ClusterRoles"
# ─────────────────────────────────────────────────────────────────────────────

WILDCARD_ROLES=$(kubectl get roles,clusterroles -A -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
# Built-in K8s ClusterRoles that legitimately use wildcards — exclude from check
BUILTIN_ROLES = {'cluster-admin', 'admin', 'edit', 'view'}
for item in data.get('items', []):
    name = item.get('metadata', {}).get('name', '')
    ns = item.get('metadata', {}).get('namespace', 'cluster')
    if name.startswith('system:') or name.startswith('kubeadm'): continue
    if name in BUILTIN_ROLES: continue   # skip built-in roles
    for rule in item.get('rules', []):
        if '*' in rule.get('verbs', []) or \
           '*' in rule.get('resources', []) or \
           '*' in rule.get('apiGroups', []):
            print(f'{ns}/{name}: has wildcard [*]')
" 2>/dev/null)

if [ -z "$WILDCARD_ROLES" ]; then
  pass "No non-system roles with wildcard permissions"
else
  while IFS= read -r line; do
    fail "Wildcard role found: $line"
  done <<< "$WILDCARD_ROLES"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "5.1.4 — Minimize access to create pods"
# ─────────────────────────────────────────────────────────────────────────────

POD_CREATE_ROLES=$(kubectl get roles,clusterroles -A -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    name = item.get('metadata', {}).get('name', '')
    ns = item.get('metadata', {}).get('namespace', 'cluster')
    if name.startswith('system:') or name.startswith('kubeadm'): continue
    for rule in item.get('rules', []):
        if ('pods' in rule.get('resources', []) or '*' in rule.get('resources', [])) and \
           ('create' in rule.get('verbs', []) or '*' in rule.get('verbs', [])):
            print(f'{ns}/{name}: can create pods')
" 2>/dev/null)

if [ -z "$POD_CREATE_ROLES" ]; then
  pass "No non-system roles with pod create access"
else
  while IFS= read -r line; do
    warn "Role can create pods: $line"
  done <<< "$POD_CREATE_ROLES"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "5.1.5 — Default ServiceAccounts not actively used"
# ─────────────────────────────────────────────────────────────────────────────

APP_NAMESPACES=("tesco-core" "tesco-payments" "tesco-frontend" "tesco-data" "tesco-messaging" "tesco-monitoring")

for ns in "${APP_NAMESPACES[@]}"; do
  # Check if any pods use the default SA
  PODS_WITH_DEFAULT=$(kubectl get pods -n "$ns" \
    -o jsonpath='{range .items[?(@.spec.serviceAccountName=="default")]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

  if [ -z "$PODS_WITH_DEFAULT" ]; then
    pass "$ns: no pods using default ServiceAccount"
  else
    while IFS= read -r pod; do
      fail "$ns/$pod is using the default ServiceAccount"
    done <<< "$PODS_WITH_DEFAULT"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
section "5.1.6 — SA tokens only mounted where necessary"
# ─────────────────────────────────────────────────────────────────────────────

# Check automountServiceAccountToken on default SAs
for ns in "${APP_NAMESPACES[@]}"; do
  TOKEN_MOUNT=$(kubectl get serviceaccount default -n "$ns" \
    -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null)

  if [ "$TOKEN_MOUNT" = "false" ]; then
    pass "$ns/default SA: automountServiceAccountToken=false"
  else
    fail "$ns/default SA: automountServiceAccountToken=$TOKEN_MOUNT (should be false)"
  fi
done

# Check custom SAs
echo ""
info "Custom ServiceAccount token status:"
for ns in "${APP_NAMESPACES[@]}"; do
  SAs=$(kubectl get serviceaccounts -n "$ns" \
    --no-headers -o custom-columns="NAME:.metadata.name" 2>/dev/null \
    | grep -v "^default$")

  while IFS= read -r sa; do
    [ -z "$sa" ] && continue
    MOUNT=$(kubectl get serviceaccount "$sa" -n "$ns" \
      -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null)
    if [ "$MOUNT" = "false" ]; then
      pass "$ns/$sa: automountServiceAccountToken=false"
    else
      fail "$ns/$sa: automountServiceAccountToken=$MOUNT (should be false)"
    fi
  done <<< "$SAs"
done

# ─────────────────────────────────────────────────────────────────────────────
section "5.1.7 — No system:masters group usage"
# ─────────────────────────────────────────────────────────────────────────────

MASTERS_BINDINGS=$(kubectl get clusterrolebindings,rolebindings -A -o json 2>/dev/null | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
# cluster-admin → system:masters is the built-in kubeadm binding — expected and required
BUILTIN_BINDINGS = {'cluster-admin'}
for item in data.get('items', []):
    name = item.get('metadata', {}).get('name', '')
    if name in BUILTIN_BINDINGS: continue
    for subj in item.get('subjects', []):
        if subj.get('name') == 'system:masters':
            print(f'{name}: binds system:masters')
" 2>/dev/null)

if [ -z "$MASTERS_BINDINGS" ]; then
  pass "No non-system bindings to system:masters group"
  info "Note: cluster-admin → system:masters is expected (built-in kubeadm binding)"
else
  while IFS= read -r line; do
    fail "Unexpected system:masters binding: $line"
  done <<< "$MASTERS_BINDINGS"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Verify — SA tokens NOT actually mounted in running pods"
# ─────────────────────────────────────────────────────────────────────────────

CHECK_PODS=(
  "tesco-core:deploy/product-service"
  "tesco-core:deploy/cart-service"
  "tesco-core:deploy/order-service"
  "tesco-payments:deploy/payment-service"
  "tesco-frontend:deploy/frontend"
)

for entry in "${CHECK_PODS[@]}"; do
  NS="${entry%%:*}"
  DEPLOY="${entry##*:}"

  # Use pod spec inspection instead of kubectl exec — avoids Kind's x509 kubelet TLS issue
  # (Kind worker nodes use IPs not in kubelet cert SANs, causing exec TLS failures)
  POD_NAME=$(kubectl get pods -n "$NS" -l "app=${DEPLOY##*/}" \
    --no-headers -o custom-columns="NAME:.metadata.name" 2>/dev/null | head -1)

  if [ -z "$POD_NAME" ]; then
    # Fallback: get first pod from deploy
    POD_NAME=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null \
      | grep "${DEPLOY##*\/}" | head -1 | awk '{print $1}')
  fi

  if [ -z "$POD_NAME" ]; then
    warn "$NS/$DEPLOY: could not find pod to inspect"
    continue
  fi

  # Check via pod spec: automountServiceAccountToken at pod level
  POD_AUTOMOUNT=$(kubectl get pod "$POD_NAME" -n "$NS" \
    -o jsonpath='{.spec.automountServiceAccountToken}' 2>/dev/null)

  # Check if kube-api-access projected volume exists in pod spec
  HAS_TOKEN_VOL=$(kubectl get pod "$POD_NAME" -n "$NS" -o json 2>/dev/null | \
    python3 -c "
import json, sys
pod = json.load(sys.stdin)
vols = pod.get('spec', {}).get('volumes') or []
has_token = any(
    'kube-api-access' in v.get('name', '') or
    'service-account-token' in v.get('name', '')
    for v in vols
)
print('true' if has_token else 'false')
" 2>/dev/null)

  if [ "$HAS_TOKEN_VOL" = "false" ]; then
    pass "$NS/$DEPLOY ($POD_NAME): no SA token volume in pod spec"
  elif [ "$POD_AUTOMOUNT" = "false" ]; then
    pass "$NS/$DEPLOY ($POD_NAME): automountServiceAccountToken=false on pod spec"
  else
    fail "$NS/$DEPLOY ($POD_NAME): SA token may be mounted (automount=$POD_AUTOMOUNT, tokenVol=$HAS_TOKEN_VOL)"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
section "Verify — No Roles/ClusterRoles bound to FreshMart service accounts"
# ─────────────────────────────────────────────────────────────────────────────

FRESHMART_SAS=(
  "tesco-core:product-service-sa"
  "tesco-core:cart-service-sa"
  "tesco-core:order-service-sa"
  "tesco-payments:payment-service-sa"
  "tesco-frontend:frontend-sa"
)

for entry in "${FRESHMART_SAS[@]}"; do
  NS="${entry%%:*}"
  SA="${entry##*:}"

  ROLE_BINDINGS=$(kubectl get rolebindings,clusterrolebindings -A -o json 2>/dev/null | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
found = []
for item in data.get('items', []):
    for subj in item.get('subjects', []):
        if subj.get('kind') == 'ServiceAccount' and \
           subj.get('name') == '$SA' and \
           subj.get('namespace') == '$NS':
            found.append(item.get('metadata', {}).get('name', 'unknown'))
for f in found:
    print(f)
" 2>/dev/null)

  if [ -z "$ROLE_BINDINGS" ]; then
    pass "$NS/$SA: no Role/ClusterRole bound (correct — no K8s API access needed)"
  else
    warn "$NS/$SA: has Role binding(s): $ROLE_BINDINGS"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
section "Summary — All ClusterRoleBindings (for manual review)"
# ─────────────────────────────────────────────────────────────────────────────

echo ""
kubectl get clusterrolebindings \
  -o custom-columns="NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*].name" \
  | grep -v "^system:\|^kubeadm\|^kindnet\|^local-path\|^ingress\|^kube-proxy\|^coredns" \
  | head -20

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
echo -e "  Results: ${GREEN}${PASS} passed${NC}  |  ${RED}${FAIL} failed${NC}  |  ${YELLOW}${WARN} warnings${NC}"
echo "════════════════════════════════════════════════════"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "  To fix default SA patches:"
  echo "  kubectl apply -f k8s/10-rbac-hardening/default-sa-patch.yaml"
  echo ""
fi

echo "  Note: WARNs on built-in roles (cluster-admin, admin, edit,"
echo "  ingress-nginx, local-path-provisioner) are expected — these are"
echo "  system/infrastructure components, not FreshMart app roles."
echo ""
