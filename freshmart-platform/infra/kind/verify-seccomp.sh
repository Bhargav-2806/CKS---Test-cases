#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# FreshMart — seccomp Verification Script
# Run after setup-seccomp.sh to confirm profiles are active and enforcing
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0; WARN=0

pass() { echo -e "  ${GREEN}✅ PASS${NC}  $*"; ((PASS++)); }
fail() { echo -e "  ${RED}❌ FAIL${NC}  $*"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}⚠️  WARN${NC}  $*"; ((WARN++)); }
section() { echo ""; echo -e "${BLUE}── $* ──────────────────────────────────${NC}"; }

CLUSTER_NAME="freshmart-cks"
SECCOMP_PATH="/var/lib/kubelet/seccomp/freshmart"
ALL_NODES=$(kind get nodes --name "$CLUSTER_NAME" 2>/dev/null)

echo ""
echo "════════════════════════════════════════════════════"
echo "  FreshMart Phase 4.5 — seccomp Verification"
echo "════════════════════════════════════════════════════"

# ─── Test 1: Profiles exist on all nodes ─────────────────────────────────────
section "Test 1 — Profile files exist on all nodes"
for node in $ALL_NODES; do
  for profile in freshmart-python.json freshmart-payment.json freshmart-frontend.json; do
    if docker exec "$node" test -f "$SECCOMP_PATH/$profile" 2>/dev/null; then
      pass "$node: $profile present"
    else
      fail "$node: $profile MISSING from $SECCOMP_PATH"
    fi
  done
done

# ─── Test 2: Pod specs reference Localhost profiles ───────────────────────────
section "Test 2 — Pod specs use Localhost seccomp profiles"
EXPECTED_PROFILES=(
  "tesco-core:product-service:freshmart/freshmart-python.json"
  "tesco-core:cart-service:freshmart/freshmart-python.json"
  "tesco-core:order-service:freshmart/freshmart-python.json"
  "tesco-payments:payment-service:freshmart/freshmart-payment.json"
  "tesco-frontend:frontend:freshmart/freshmart-frontend.json"
)

for entry in "${EXPECTED_PROFILES[@]}"; do
  NS="${entry%%:*}"; rest="${entry#*:}"
  APP="${rest%%:*}"; EXPECTED="${rest##*:}"

  TYPE=$(kubectl get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[0].spec.securityContext.seccompProfile.type}' 2>/dev/null)
  PROFILE=$(kubectl get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[0].spec.securityContext.seccompProfile.localhostProfile}' 2>/dev/null)

  if [ "$TYPE" = "Localhost" ] && [ "$PROFILE" = "$EXPECTED" ]; then
    pass "$NS/$APP → type=Localhost profile=$PROFILE"
  else
    fail "$NS/$APP → type=$TYPE profile=$PROFILE (expected Localhost/$EXPECTED)"
  fi
done

# ─── Test 3: Pods are Running (profile not breaking services) ─────────────────
section "Test 3 — All pods Running with custom seccomp"
for ns_app in \
  "tesco-core:product-service" \
  "tesco-core:cart-service" \
  "tesco-core:order-service" \
  "tesco-payments:payment-service" \
  "tesco-frontend:frontend"; do
  NS="${ns_app%%:*}"; APP="${ns_app##*:}"
  READY=$(kubectl get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
  if [ "$READY" = "true" ]; then
    pass "$NS/$APP: Running ✓"
  else
    fail "$NS/$APP: NOT ready (status=$READY)"
  fi
done

# ─── Test 4: API smoke test ───────────────────────────────────────────────────
section "Test 4 — APIs working under custom seccomp"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/products 2>/dev/null)
[ "$HTTP_CODE" = "200" ] \
  && pass "Products API: HTTP 200 ✓" \
  || fail "Products API: HTTP $HTTP_CODE"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost/api/cart/seccomp-test/items \
  -H "Content-Type: application/json" \
  -d '{"product_id":1,"quantity":1}' 2>/dev/null)
[ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] \
  && pass "Cart API: HTTP $HTTP_CODE ✓" \
  || fail "Cart API: HTTP $HTTP_CODE"

# ─── Test 5: seccomp mode in /proc (pid 1 inside container) ─────────────────
section "Test 5 — Verify seccomp is active at process level"
for ns_app in "tesco-core:product-service" "tesco-payments:payment-service"; do
  NS="${ns_app%%:*}"; APP="${ns_app##*:}"
  POD=$(kubectl get pods -n "$NS" -l "app=$APP" \
    --no-headers -o custom-columns="N:.metadata.name" | head -1)

  # Read /proc/1/status — Seccomp line: 0=disabled, 1=strict, 2=filter
  SECCOMP_MODE=$(kubectl exec -n "$NS" "$POD" -- \
    sh -c "grep Seccomp /proc/1/status 2>/dev/null || cat /proc/1/status | grep -i seccomp" \
    2>/dev/null | awk '{print $2}')

  if [ "$SECCOMP_MODE" = "2" ]; then
    pass "$NS/$APP ($POD): Seccomp mode=2 (filter/custom) ✓"
  elif [ "$SECCOMP_MODE" = "0" ]; then
    fail "$NS/$APP ($POD): Seccomp mode=0 (DISABLED) — profile not applied"
  else
    warn "$NS/$APP ($POD): Seccomp mode=$SECCOMP_MODE (1=strict, 2=filter expected)"
  fi
done

# ─── Test 6: Dangerous syscall blocked ───────────────────────────────────────
section "Test 6 — Dangerous syscall blocked (ptrace → KILL_PROCESS)"
# Try to call ptrace from inside product-service — should be killed or EPERM
# We use python's ctypes to make the syscall directly
POD=$(kubectl get pods -n tesco-core -l app=product-service \
  --no-headers -o custom-columns="N:.metadata.name" | head -1)

RESULT=$(kubectl exec -n tesco-core "$POD" -- \
  python3 -c "
import ctypes, sys
PTRACE_TRACEME = 0
libc = ctypes.CDLL(None, use_errno=True)
ret = libc.syscall(101, PTRACE_TRACEME, 0, 0, 0)  # 101 = ptrace syscall
err = ctypes.get_errno()
if ret == -1:
    print(f'BLOCKED: ptrace returned -1, errno={err}')
else:
    print(f'ALLOWED: ptrace returned {ret} (BAD - should be blocked)')
" 2>&1)

if echo "$RESULT" | grep -q "BLOCKED"; then
  pass "product-service: ptrace blocked ✓ ($RESULT)"
elif echo "$RESULT" | grep -qiE "killed|operation not permitted|bad system call"; then
  pass "product-service: ptrace blocked by seccomp ✓"
else
  warn "product-service: ptrace result: $RESULT"
fi

# ─── Test 7: JSON profile syntax valid ───────────────────────────────────────
section "Test 7 — Profile JSON syntax valid"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for profile in "$ROOT_DIR/k8s/12-seccomp/profiles/"*.json; do
  name=$(basename "$profile")
  if python3 -c "import json; json.load(open('$profile'))" 2>/dev/null; then
    pass "$name: valid JSON"
  else
    fail "$name: INVALID JSON"
  fi
done

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
echo -e "  Results: ${GREEN}${PASS} passed${NC}  |  ${RED}${FAIL} failed${NC}  |  ${YELLOW}${WARN} warnings${NC}"
echo "════════════════════════════════════════════════════"
echo ""
