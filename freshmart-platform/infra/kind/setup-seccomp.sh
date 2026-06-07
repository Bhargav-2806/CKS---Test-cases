#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# FreshMart — Phase 4.5: Custom seccomp Profiles
# CKS Domain: System Hardening (15%)
#
# Unlike AppArmor, seccomp WORKS on macOS + Kind (Docker Desktop supports it).
# Profiles are loaded via kubelet from /var/lib/kubelet/seccomp/ on each node.
#
# What this script does:
#   1. Creates /var/lib/kubelet/seccomp/freshmart/ on every node
#   2. Copies JSON profiles to each node
#   3. Patches deployments to use Localhost seccomp (replaces RuntimeDefault)
#   4. Rolls out and verifies
#
# Usage:
#   chmod +x infra/kind/setup-seccomp.sh
#   ./infra/kind/setup-seccomp.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CLUSTER_NAME="freshmart-cks"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROFILES_DIR="$ROOT_DIR/k8s/12-seccomp/profiles"
SECCOMP_PATH="/var/lib/kubelet/seccomp/freshmart"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─── Pre-flight ───────────────────────────────────────────────────────────────
log "Checking cluster..."
kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME" \
  || die "Cluster '$CLUSTER_NAME' not found. Run setup.sh first."
kubectl cluster-info --request-timeout=5s &>/dev/null \
  || die "Cannot reach cluster API server."
ok "Cluster ready"

ALL_NODES=$(kind get nodes --name "$CLUSTER_NAME" 2>/dev/null)

# ─── Step 1: Copy profiles to every node ─────────────────────────────────────
log "Copying seccomp profiles to all nodes..."
for node in $ALL_NODES; do
  # Create seccomp directory on node
  docker exec "$node" mkdir -p "$SECCOMP_PATH"

  # Copy each profile
  for profile in freshmart-python.json freshmart-payment.json freshmart-frontend.json; do
    docker cp "$PROFILES_DIR/$profile" "$node:$SECCOMP_PATH/$profile"
    docker exec "$node" chmod 644 "$SECCOMP_PATH/$profile"
    ok "$node: copied $profile"
  done

  # Verify they're there
  docker exec "$node" ls -la "$SECCOMP_PATH/"
done

# ─── Step 2: Verify kubelet can see the profiles ──────────────────────────────
log "Verifying profiles on nodes..."
for node in $ALL_NODES; do
  COUNT=$(docker exec "$node" ls "$SECCOMP_PATH/" | wc -l | tr -d ' ')
  ok "$node: $COUNT profiles available at $SECCOMP_PATH"
done

# ─── Step 3: Patch deployments to use Localhost seccomp ──────────────────────
log "Patching deployments: RuntimeDefault → Localhost custom profiles..."

# Python services — product, cart, order
for deploy in product-service cart-service order-service; do
  kubectl patch deployment "$deploy" -n tesco-core --type=json -p="[
    {
      \"op\": \"replace\",
      \"path\": \"/spec/template/spec/securityContext/seccompProfile\",
      \"value\": {
        \"type\": \"Localhost\",
        \"localhostProfile\": \"freshmart/freshmart-python.json\"
      }
    }
  ]" && ok "Patched $deploy → freshmart/freshmart-python.json"
done

# payment-service
kubectl patch deployment payment-service -n tesco-payments --type=json -p="[
  {
    \"op\": \"replace\",
    \"path\": \"/spec/template/spec/securityContext/seccompProfile\",
    \"value\": {
      \"type\": \"Localhost\",
      \"localhostProfile\": \"freshmart/freshmart-payment.json\"
    }
  }
]" && ok "Patched payment-service → freshmart/freshmart-payment.json"

# frontend
kubectl patch deployment frontend -n tesco-frontend --type=json -p="[
  {
    \"op\": \"replace\",
    \"path\": \"/spec/template/spec/securityContext/seccompProfile\",
    \"value\": {
      \"type\": \"Localhost\",
      \"localhostProfile\": \"freshmart/freshmart-frontend.json\"
    }
  }
]" && ok "Patched frontend → freshmart/freshmart-frontend.json"

# ─── Step 4: Wait for rollouts ────────────────────────────────────────────────
log "Waiting for rollouts..."
for ns_deploy in \
  "tesco-core:product-service" \
  "tesco-core:cart-service" \
  "tesco-core:order-service" \
  "tesco-payments:payment-service" \
  "tesco-frontend:frontend"; do
  NS="${ns_deploy%%:*}"; DEPLOY="${ns_deploy##*:}"
  kubectl rollout status deployment/"$DEPLOY" -n "$NS" --timeout=90s \
    && ok "$NS/$DEPLOY ready"
done

# ─── Step 5: Verify seccomp profile in pod spec ──────────────────────────────
log "Verifying seccomp profiles in pod specs..."
echo ""
for ns_app in \
  "tesco-core:product-service" \
  "tesco-core:cart-service" \
  "tesco-core:order-service" \
  "tesco-payments:payment-service" \
  "tesco-frontend:frontend"; do
  NS="${ns_app%%:*}"; APP="${ns_app##*:}"
  PROFILE=$(kubectl get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[0].spec.securityContext.seccompProfile}' 2>/dev/null)
  echo "  $NS/$APP → seccompProfile: $PROFILE"
done

# ─── Step 6: Verify APIs still work ──────────────────────────────────────────
echo ""
log "Smoke test — verifying services still respond..."
sleep 5
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/products 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
  ok "Products API: HTTP $HTTP_CODE ✓ (seccomp profile not breaking service)"
else
  warn "Products API: HTTP $HTTP_CODE — check deployment logs if unexpected"
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Phase 4.5 — Custom seccomp Profiles Applied!        ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo "  Profile locations on nodes: $SECCOMP_PATH"
echo "  Profile referenced in pods: freshmart/freshmart-*.json"
echo ""
echo "  Verify with:"
echo "  kubectl get pod -n tesco-core -l app=product-service \\"
echo "    -o jsonpath='{.items[0].spec.securityContext.seccompProfile}'"
echo ""
echo "  Run full verification:"
echo "  ./infra/kind/verify-seccomp.sh"
echo ""
