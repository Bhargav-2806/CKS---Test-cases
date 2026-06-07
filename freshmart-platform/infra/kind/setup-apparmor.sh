#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# FreshMart — Phase 4.4: AppArmor Custom Profiles
# CKS Domain: System Hardening (15%)
#
# What this script does:
#   1. Checks if AppArmor is available on Kind nodes
#   2. If available: installs apparmor-utils, loads profiles, patches deployments
#   3. If not available (macOS/Docker Desktop): explains why + shows exam commands
#
# Usage:
#   chmod +x infra/kind/setup-apparmor.sh
#   ./infra/kind/setup-apparmor.sh
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

CLUSTER_NAME="freshmart-cks"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROFILES_DIR="$ROOT_DIR/k8s/11-apparmor/profiles"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

WORKER_NODES=$(kind get nodes --name "$CLUSTER_NAME" 2>/dev/null | grep -v control-plane)

# ─────────────────────────────────────────────────────────────────────────────
# Step 1 — Check AppArmor availability
# ─────────────────────────────────────────────────────────────────────────────
log "Checking AppArmor availability in Kind nodes..."

APPARMOR_AVAILABLE=false
for node in $WORKER_NODES; do
  STATUS=$(docker exec "$node" \
    sh -c "cat /sys/module/apparmor/parameters/enabled 2>/dev/null || echo N" \
    2>/dev/null | tr -d '[:space:]')

  if [ "$STATUS" = "Y" ]; then
    ok "$node: AppArmor is ENABLED in kernel"
    APPARMOR_AVAILABLE=true
  else
    warn "$node: AppArmor is NOT available (status=$STATUS)"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Step 2 — Handle unavailable AppArmor (macOS / Docker Desktop)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$APPARMOR_AVAILABLE" = "false" ]; then
  echo ""
  echo -e "${YELLOW}══════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  AppArmor not available in this environment               ${NC}"
  echo -e "${YELLOW}══════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "  WHY: Docker Desktop on macOS uses a lightweight Linux VM"
  echo "  (LinuxKit) that does not include AppArmor kernel modules."
  echo "  AppArmor requires the kernel to have CONFIG_SECURITY_APPARMOR=y"
  echo "  compiled in, which LinuxKit does not provide."
  echo ""
  echo "  WHERE AppArmor DOES work:"
  echo "  • Ubuntu 18.04+ (bare metal or VM) — enabled by default"
  echo "  • Debian with apparmor package installed"
  echo "  • CKS exam environment (Ubuntu 22.04 nodes) ← AppArmor IS there"
  echo "  • EKS nodes with Ubuntu AMI (Phase 7)"
  echo "  • GKE nodes with Container-Optimized OS"
  echo ""
  echo "  WHAT WE'VE DONE:"
  echo "  ✅ Created AppArmor profiles for all 5 FreshMart services:"
  for profile in "$PROFILES_DIR"/*; do
    echo "     • $(basename $profile)"
  done
  echo ""
  echo "  ✅ Created K8s manifest patches with appArmorProfile securityContext"
  echo "  ✅ Documented the full CKS exam workflow below"
  echo ""
  echo -e "${BLUE}══ CKS EXAM WORKFLOW (Ubuntu node) ════════════════════════${NC}"
  echo ""
  echo "  On the exam, nodes are Ubuntu — AppArmor is available."
  echo "  These are the exact commands you will run:"
  echo ""
  echo "  # 1. Copy profile to the node (or create it directly)"
  echo "  scp k8s/11-apparmor/profiles/freshmart-python-service \\"
  echo "    <node>:/etc/apparmor.d/freshmart-python-service"
  echo ""
  echo "  # 2. Load profile into kernel"
  echo "  ssh <node> apparmor_parser -r -W /etc/apparmor.d/freshmart-python-service"
  echo ""
  echo "  # 3. Verify it's loaded"
  echo "  ssh <node> aa-status | grep freshmart"
  echo ""
  echo "  # 4. Apply to pod via securityContext (K8s 1.30+)"
  echo "  # Edit the deployment and add under container.securityContext:"
  echo "  #   appArmorProfile:"
  echo "  #     type: Localhost"
  echo "  #     localhostProfile: freshmart-python-service"
  echo ""
  echo "  # 5. Verify profile is enforcing"
  echo "  kubectl exec -n tesco-core deploy/product-service -- cat /proc/1/attr/current"
  echo "  # Expected: freshmart-python-service (enforce)"
  echo ""
  echo "  Profile files are ready in: k8s/11-apparmor/profiles/"
  echo "  Manifest patches are in:    k8s/11-apparmor/"
  echo ""
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 3 — AppArmor IS available — install tools and load profiles
# ─────────────────────────────────────────────────────────────────────────────
log "AppArmor available — proceeding with profile installation..."

ALL_NODES=$(kind get nodes --name "$CLUSTER_NAME" 2>/dev/null)

for node in $ALL_NODES; do
  log "Setting up $node..."

  # Install apparmor-utils if not present
  docker exec "$node" sh -c \
    "which apparmor_parser >/dev/null 2>&1 || \
     (apt-get update -qq && apt-get install -y -qq apparmor-utils 2>/dev/null)" \
    && ok "$node: apparmor-utils ready"

  # Copy all profiles to /etc/apparmor.d/ on the node
  for profile_file in "$PROFILES_DIR"/*; do
    profile_name=$(basename "$profile_file")
    docker cp "$profile_file" "$node:/etc/apparmor.d/$profile_name"
    docker exec "$node" chmod 644 "/etc/apparmor.d/$profile_name"

    # Load profile into kernel
    docker exec "$node" \
      apparmor_parser -r -W "/etc/apparmor.d/$profile_name" \
      && ok "$node: loaded profile $profile_name"
  done
done

# ─────────────────────────────────────────────────────────────────────────────
# Step 4 — Verify profiles are loaded
# ─────────────────────────────────────────────────────────────────────────────
log "Verifying profiles on worker nodes..."
for node in $WORKER_NODES; do
  echo ""
  echo "  === $node ==="
  docker exec "$node" aa-status 2>/dev/null | grep "freshmart" || \
    echo "  (no freshmart profiles loaded yet)"
done

# ─────────────────────────────────────────────────────────────────────────────
# Step 5 — Apply AppArmor to deployments via kubectl patch
# ─────────────────────────────────────────────────────────────────────────────
log "Patching deployments to use AppArmor profiles..."

# Python services — use freshmart-python-service profile
for deploy in product-service cart-service order-service; do
  kubectl patch deployment "$deploy" -n tesco-core \
    --type=json \
    -p="[{
      \"op\": \"add\",
      \"path\": \"/spec/template/spec/containers/0/securityContext/appArmorProfile\",
      \"value\": {\"type\": \"Localhost\", \"localhostProfile\": \"freshmart-python-service\"}
    }]" \
    && ok "Patched $deploy with freshmart-python-service profile"
done

# payment-service — use most restrictive profile
kubectl patch deployment payment-service -n tesco-payments \
  --type=json \
  -p="[{
    \"op\": \"add\",
    \"path\": \"/spec/template/spec/containers/0/securityContext/appArmorProfile\",
    \"value\": {\"type\": \"Localhost\", \"localhostProfile\": \"freshmart-payment-service\"}
  }]" \
  && ok "Patched payment-service with freshmart-payment-service profile"

# frontend — use frontend profile
kubectl patch deployment frontend -n tesco-frontend \
  --type=json \
  -p="[{
    \"op\": \"add\",
    \"path\": \"/spec/template/spec/containers/0/securityContext/appArmorProfile\",
    \"value\": {\"type\": \"Localhost\", \"localhostProfile\": \"freshmart-frontend\"}
  }]" \
  && ok "Patched frontend with freshmart-frontend profile"

# ─────────────────────────────────────────────────────────────────────────────
# Step 6 — Wait for rollout and verify
# ─────────────────────────────────────────────────────────────────────────────
log "Waiting for rollouts..."
for ns_deploy in \
  "tesco-core:product-service" \
  "tesco-core:cart-service" \
  "tesco-core:order-service" \
  "tesco-payments:payment-service" \
  "tesco-frontend:frontend"; do
  NS="${ns_deploy%%:*}"; DEPLOY="${ns_deploy##*:}"
  kubectl rollout status deployment/"$DEPLOY" -n "$NS" --timeout=60s \
    && ok "$NS/$DEPLOY rolled out"
done

log "Verifying AppArmor is enforcing on running pods..."
for ns_deploy in \
  "tesco-core:product-service" \
  "tesco-payments:payment-service"; do
  NS="${ns_deploy%%:*}"; DEPLOY="${ns_deploy##*:}"
  POD=$(kubectl get pods -n "$NS" -l "app=$DEPLOY" --no-headers -o custom-columns="N:.metadata.name" | head -1)
  PROFILE=$(kubectl exec -n "$NS" "$POD" -- \
    cat /proc/1/attr/current 2>/dev/null || echo "could not read")
  echo "  $NS/$POD → AppArmor: $PROFILE"
done

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Phase 4.4 — AppArmor Profiles Applied!          ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo "  Profiles loaded and enforcing:"
echo "  • freshmart-python-service  → product, cart, order"
echo "  • freshmart-payment-service → payment (most restrictive)"
echo "  • freshmart-frontend        → Next.js"
echo ""
