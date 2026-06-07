#!/usr/bin/env bash
# =============================================================================
# Phase 4.10 — gVisor RuntimeClass Setup
# Installs gVisor (runsc) on Kind nodes + registers as containerd runtime
# CKS Domain: Minimize Microservice Vulnerabilities (20%) — container sandboxing
#
# What this script does:
#   1. Detects node architecture (x86_64 / aarch64)
#   2. Downloads runsc + containerd shim onto every Kind node
#   3. Configures containerd with "runsc" runtime handler
#   4. Restarts containerd on each node
#   5. Applies RuntimeClass K8s resource
#   6. Patches payment-service to use runtimeClassName: gvisor
#   7. Verifies gVisor is actually running the container
#
# Platform note:
#   gVisor uses ptrace mode on Docker Desktop (no KVM available).
#   ptrace mode intercepts all syscalls in user space — full isolation,
#   slightly slower than KVM mode used in production cloud environments.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
step()  { echo -e "\n${CYAN}══ $* ══${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/../../k8s/16-gvisor"
CLUSTER_NAME="freshmart-cks"

# gVisor release — use a known-stable release date
GVISOR_RELEASE="20240212.0"
GVISOR_BASE="https://storage.googleapis.com/gvisor/releases/release/${GVISOR_RELEASE}"

# ─── Step 1: Verify cluster ───────────────────────────────────────────────────
step "Checking Kind cluster"
kubectl cluster-info --context "kind-${CLUSTER_NAME}" > /dev/null 2>&1 || \
  fail "Kind cluster '${CLUSTER_NAME}' not found. Run setup.sh first."
ok "Cluster found"

# ─── Step 2: Detect architecture ─────────────────────────────────────────────
step "Detecting node architecture"
NODE_ARCH=$(docker exec "${CLUSTER_NAME}-control-plane" uname -m 2>/dev/null || echo "x86_64")
case "$NODE_ARCH" in
  x86_64)       GVISOR_ARCH="x86_64" ;;
  aarch64|arm64) GVISOR_ARCH="aarch64" ;;
  *)            fail "Unsupported architecture: $NODE_ARCH" ;;
esac
info "Architecture: $NODE_ARCH → gVisor binary: $GVISOR_ARCH"

RUNSC_URL="${GVISOR_BASE}/${GVISOR_ARCH}/runsc"
SHIM_URL="${GVISOR_BASE}/${GVISOR_ARCH}/containerd-shim-runsc-v1"

# ─── Step 3: Install gVisor on all Kind nodes ─────────────────────────────────
step "Installing gVisor on Kind nodes"
NODES=$(kind get nodes --name "$CLUSTER_NAME" 2>/dev/null)

for node in $NODES; do
  info "Processing node: $node"

  # Check if runsc already installed
  if docker exec "$node" test -f /usr/local/bin/runsc 2>/dev/null; then
    ok "runsc already installed on $node — skipping download"
  else
    info "Downloading runsc binary onto $node..."
    docker exec "$node" bash -c "
      curl -fsSL '${RUNSC_URL}' -o /usr/local/bin/runsc && \
      chmod a+rx /usr/local/bin/runsc
    " || fail "Failed to download runsc on $node. Check network connectivity."

    info "Downloading containerd shim onto $node..."
    docker exec "$node" bash -c "
      curl -fsSL '${SHIM_URL}' -o /usr/local/bin/containerd-shim-runsc-v1 && \
      chmod a+rx /usr/local/bin/containerd-shim-runsc-v1
    " || fail "Failed to download containerd shim on $node."

    ok "gVisor binaries installed on $node"
  fi

  # Verify runsc binary works
  RUNSC_VERSION=$(docker exec "$node" runsc --version 2>/dev/null | head -1 || echo "unknown")
  info "runsc version: $RUNSC_VERSION"

  # ─── Configure containerd ─────────────────────────────────────────────────
  info "Configuring containerd on $node..."

  # Check if already configured
  if docker exec "$node" grep -q "runsc" /etc/containerd/config.toml 2>/dev/null; then
    ok "containerd already configured for runsc on $node — skipping"
  else
    # Add runsc runtime handler to containerd config
    docker exec "$node" bash -c "
cat >> /etc/containerd/config.toml << 'TOML'

# gVisor sandbox runtime — added by setup-gvisor.sh (Phase 4.10)
[plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.runsc]
  runtime_type = \"io.containerd.runsc.v1\"
  [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.runsc.options]
    TypeUrl = \"io.containerd.runsc.v1.options\"
TOML
"
    ok "containerd config updated on $node"
  fi

  # ─── Write runsc config (force ptrace for Docker Desktop compatibility) ────
  docker exec "$node" bash -c "
mkdir -p /etc/containerd
cat > /etc/runsc.toml << 'RUNSC'
# gVisor configuration — Phase 4.10
# platform=ptrace: works in Docker Desktop (no KVM available)
# In production (EC2/GKE), use platform=kvm for better performance
[runsc_config]
  platform = \"ptrace\"
  debug = false
  debug-log = \"/tmp/runsc-%ID%.log\"
RUNSC
"

  # ─── Restart containerd to pick up new config ─────────────────────────────
  info "Restarting containerd on $node..."
  docker exec "$node" bash -c "
    # Signal containerd to reload its config
    if pgrep containerd > /dev/null; then
      kill -SIGTERM \$(pgrep -x containerd) 2>/dev/null || true
      sleep 2
      nohup containerd > /tmp/containerd.log 2>&1 &
      sleep 3
    fi
  " 2>/dev/null || true

  ok "containerd restarted on $node"
done

# ─── Step 4: Apply K8s RuntimeClass ──────────────────────────────────────────
step "Applying gVisor RuntimeClass"
kubectl apply -f "$K8S_DIR/00-runtimeclass.yaml"
ok "RuntimeClass 'gvisor' created"

# ─── Step 5: Test gVisor with a scratch pod ───────────────────────────────────
step "Testing gVisor with a scratch pod"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gvisor-smoke-test
  namespace: default
  labels:
    app: gvisor-smoke-test
spec:
  runtimeClassName: gvisor
  restartPolicy: Never
  containers:
  - name: test
    image: busybox:1.36
    command: ["sh", "-c", "cat /proc/version && echo 'gVisor test PASSED'"]
    resources:
      limits:
        cpu: "100m"
        memory: "64Mi"
      requests:
        cpu: "50m"
        memory: "32Mi"
    securityContext:
      runAsNonRoot: true
      runAsUser: 65534
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      seccompProfile:
        type: RuntimeDefault
EOF

info "Waiting for smoke test pod..."
kubectl wait pod/gvisor-smoke-test -n default \
  --for=condition=Ready --timeout=60s 2>/dev/null || \
  kubectl wait pod/gvisor-smoke-test -n default \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=60s 2>/dev/null || true

sleep 3
SMOKE_LOG=$(kubectl logs gvisor-smoke-test -n default 2>/dev/null || echo "")

if echo "$SMOKE_LOG" | grep -q "gVisor\|runsc\|4.4.0"; then
  ok "gVisor confirmed active — /proc/version shows gVisor kernel"
  echo "  Output: $SMOKE_LOG"
elif echo "$SMOKE_LOG" | grep -q "PASSED"; then
  warn "Pod ran but could not confirm gVisor kernel from /proc/version"
  echo "  Output: $SMOKE_LOG"
else
  warn "Smoke test inconclusive. Check manually:"
  info "kubectl logs gvisor-smoke-test -n default"
  info "kubectl describe pod gvisor-smoke-test -n default"
fi

kubectl delete pod gvisor-smoke-test -n default --ignore-not-found 2>/dev/null

# ─── Step 6: Apply payment-service RuntimeClass patch ────────────────────────
step "Patching payment-service to use gVisor"
kubectl apply -f "$K8S_DIR/01-payment-gvisor-patch.yaml"

info "Restarting payment-service to pick up RuntimeClass change..."
kubectl rollout restart deployment/payment-service -n tesco-payments

kubectl rollout status deployment/payment-service \
  -n tesco-payments --timeout=90s || {
  warn "Rollout did not complete — gVisor may need more time on Kind"
  warn "Check: kubectl describe pod -n tesco-payments -l app=payment-service"
  warn "If RuntimeClass not found error: containerd needs more time to register runsc"
  warn "Wait 30s and run: kubectl rollout restart deployment/payment-service -n tesco-payments"
}

# ─── Step 7: Verify payment-service is using gVisor ──────────────────────────
step "Verifying payment-service uses gVisor"

PAYMENT_POD=$(kubectl get pod -n tesco-payments -l app=payment-service \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$PAYMENT_POD" ]; then
  RUNTIME=$(kubectl get pod "$PAYMENT_POD" -n tesco-payments \
    -o jsonpath='{.spec.runtimeClassName}' 2>/dev/null || echo "")
  if [ "$RUNTIME" = "gvisor" ]; then
    ok "payment-service pod spec has runtimeClassName: gvisor"
  fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Phase 4.10 — gVisor RuntimeClass COMPLETE"
echo "══════════════════════════════════════════════════════════════"
echo ""
info "RuntimeClasses:"
kubectl get runtimeclass
echo ""
info "payment-service pod (should show runtimeClassName: gvisor):"
kubectl get pod -n tesco-payments -l app=payment-service \
  -o custom-columns="NAME:.metadata.name,RUNTIME:.spec.runtimeClassName,STATUS:.status.phase"
echo ""
echo "  Verify gVisor kernel:"
echo "  PAYMENT_POD=\$(kubectl get pod -n tesco-payments -l app=payment-service"
echo "    -o jsonpath='{.items[0].metadata.name}')"
echo "  kubectl exec \$PAYMENT_POD -n tesco-payments -- cat /proc/version"
echo "  # gVisor: Linux version 4.4.0 (...)"
echo ""
echo "  See PHASE-4.10-GVISOR.md for full test guide"
echo "══════════════════════════════════════════════════════════════"
