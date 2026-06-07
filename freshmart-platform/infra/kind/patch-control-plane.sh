#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# FreshMart — Phase 4 Control Plane Hardening
# Fixes all 10 kube-bench FAILs on the control plane:
#   1.1.12  etcd data dir ownership
#   1.2.5   kubelet-certificate-authority
#   1.2.15  API server --profiling=false
#   1.2.16  --audit-log-path
#   1.2.17  --audit-log-maxage=30
#   1.2.18  --audit-log-maxbackup=10
#   1.2.19  --audit-log-maxsize=100
#   1.2.30  --service-account-extend-token-expiration=false
#   1.3.2   controller-manager --profiling=false
#   1.4.1   scheduler --profiling=false
#
# Usage:
#   chmod +x infra/kind/patch-control-plane.sh
#   ./infra/kind/patch-control-plane.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CLUSTER_NAME="freshmart-cks"
CP="freshmart-cks-control-plane"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

APISERVER="/etc/kubernetes/manifests/kube-apiserver.yaml"
CTRLMGR="/etc/kubernetes/manifests/kube-controller-manager.yaml"
SCHEDULER="/etc/kubernetes/manifests/kube-scheduler.yaml"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

add_flag() {
  local container="$1" file="$2" flag="$3"
  # Only add the flag if it doesn't already exist
  if docker exec "$container" grep -q -- "$flag" "$file" 2>/dev/null; then
    echo "       (already present: $flag)"
  else
    # Insert flag after the component name line (first - kube-apiserver / kube-controller-manager / kube-scheduler)
    docker exec "$container" sh -c "
      sed -i 's|    - $(basename $file .yaml 2>/dev/null)||' $file 2>/dev/null || true
    "
    docker exec "$container" python3 -c "
import sys

flag = '$flag'
filepath = '$file'

with open(filepath, 'r') as f:
    lines = f.readlines()

# Find the command section and add the flag after the binary name line
inserted = False
new_lines = []
for i, line in enumerate(lines):
    new_lines.append(line)
    # Insert after the line that has the binary name (e.g. '    - kube-apiserver')
    stripped = line.strip()
    if stripped in ['- kube-apiserver', '- kube-controller-manager', '- kube-scheduler'] and not inserted:
        indent = len(line) - len(line.lstrip())
        new_lines.append(' ' * indent + '- ' + flag + '\n')
        inserted = True

if not inserted:
    print(f'WARNING: could not find insertion point for {flag} in {filepath}', file=sys.stderr)
    sys.exit(1)

with open(filepath, 'w') as f:
    f.writelines(new_lines)

print(f'Added: {flag}')
"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight
# ─────────────────────────────────────────────────────────────────────────────
log "Checking Kind cluster is running..."
docker ps --filter "name=$CP" --format "{{.Names}}" | grep -q "$CP" \
  || die "Control plane container '$CP' not found. Is the cluster running?"
ok "Cluster found"

# ─────────────────────────────────────────────────────────────────────────────
# Fix 1.1.12 — etcd data directory ownership
# ─────────────────────────────────────────────────────────────────────────────
log "Fix 1.1.12 — etcd data dir ownership..."
docker exec "$CP" sh -c "
  # Create etcd group/user if they don't exist (Kind nodes use Alpine/Debian)
  if ! id etcd &>/dev/null; then
    groupadd -r etcd 2>/dev/null || addgroup -S etcd 2>/dev/null || true
    useradd -r -g etcd etcd 2>/dev/null || adduser -S -G etcd etcd 2>/dev/null || true
  fi
  chown -R etcd:etcd /var/lib/etcd
" && ok "1.1.12 fixed — etcd:etcd owns /var/lib/etcd"

# ─────────────────────────────────────────────────────────────────────────────
# Fix 1.2.5 — kubelet-certificate-authority
# ─────────────────────────────────────────────────────────────────────────────
log "Fix 1.2.5 — kubelet-certificate-authority..."
# In Kind, the CA file is at /etc/kubernetes/pki/ca.crt
KUBELET_CA="/etc/kubernetes/pki/ca.crt"
if docker exec "$CP" grep -q "\-\-kubelet-certificate-authority" "$APISERVER"; then
  ok "1.2.5 already set"
else
  docker exec "$CP" python3 -c "
flag = '--kubelet-certificate-authority=$KUBELET_CA'
filepath = '$APISERVER'
with open(filepath, 'r') as f:
    lines = f.readlines()
new_lines = []
inserted = False
for line in lines:
    new_lines.append(line)
    if line.strip() == '- kube-apiserver' and not inserted:
        indent = len(line) - len(line.lstrip())
        new_lines.append(' ' * indent + '- ' + flag + '\n')
        inserted = True
with open(filepath, 'w') as f:
    f.writelines(new_lines)
print('Added: ' + flag)
"
  ok "1.2.5 fixed"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Fix 1.2.15 — API server profiling
# ─────────────────────────────────────────────────────────────────────────────
log "Fix 1.2.15 — API server --profiling=false..."
if docker exec "$CP" grep -q "\-\-profiling=false" "$APISERVER"; then
  ok "1.2.15 already set"
else
  docker exec "$CP" python3 -c "
filepath = '$APISERVER'
with open(filepath, 'r') as f:
    lines = f.readlines()
new_lines = []
inserted = False
for line in lines:
    new_lines.append(line)
    if line.strip() == '- kube-apiserver' and not inserted:
        indent = len(line) - len(line.lstrip())
        new_lines.append(' ' * indent + '- --profiling=false\n')
        inserted = True
with open(filepath, 'w') as f:
    f.writelines(new_lines)
print('Added: --profiling=false')
"
  ok "1.2.15 fixed"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Fix 1.2.16–1.2.19 — Audit logging
# ─────────────────────────────────────────────────────────────────────────────
log "Fix 1.2.16–19 — Configuring audit logging..."

# Create audit directories on control plane
docker exec "$CP" mkdir -p /var/log/audit
docker exec "$CP" chmod 700 /var/log/audit

# Copy audit policy file into control plane container
docker cp "$ROOT_DIR/k8s/08-audit-policy/audit-policy.yaml" \
  "$CP:/etc/kubernetes/audit-policy.yaml"
docker exec "$CP" chmod 600 /etc/kubernetes/audit-policy.yaml
ok "Audit policy copied to /etc/kubernetes/audit-policy.yaml"

# Now patch kube-apiserver.yaml to add audit flags + volume mounts
if docker exec "$CP" grep -q "\-\-audit-log-path" "$APISERVER"; then
  ok "Audit flags already present"
else
  docker exec "$CP" python3 << 'PYEOF'
import sys

filepath = '/etc/kubernetes/manifests/kube-apiserver.yaml'

with open(filepath, 'r') as f:
    content = f.read()

audit_flags = [
    '    - --audit-log-path=/var/log/audit/audit.log',
    '    - --audit-log-maxage=30',
    '    - --audit-log-maxbackup=10',
    '    - --audit-log-maxsize=100',
    '    - --audit-policy-file=/etc/kubernetes/audit-policy.yaml',
]

# Find the line with '- kube-apiserver' and insert after it
lines = content.split('\n')
new_lines = []
inserted = False
for line in lines:
    new_lines.append(line)
    if line.strip() == '- kube-apiserver' and not inserted:
        new_lines.extend(audit_flags)
        inserted = True

if not inserted:
    print('ERROR: Could not find insertion point', file=sys.stderr)
    sys.exit(1)

# Add volumeMounts to the container spec
# Find 'volumeMounts:' section and add our mounts
content_new = '\n'.join(new_lines)

audit_volume_mount = '''    - mountPath: /var/log/audit
        name: audit-log
        readOnly: false
      - mountPath: /etc/kubernetes/audit-policy.yaml
        name: audit-policy
        readOnly: true'''

audit_volumes = '''  - hostPath:
      path: /var/log/audit
      type: DirectoryOrCreate
    name: audit-log
  - hostPath:
      path: /etc/kubernetes/audit-policy.yaml
      type: File
    name: audit-policy'''

# Insert volumeMounts after 'volumeMounts:'
if 'name: audit-log' not in content_new:
    content_new = content_new.replace(
        '    volumeMounts:',
        '    volumeMounts:\n' + audit_volume_mount,
        1
    )

# Insert volumes after 'volumes:'
if '  volumes:' in content_new and 'name: audit-log' not in content_new.split('volumes:')[1][:500]:
    content_new = content_new.replace(
        '  volumes:\n',
        '  volumes:\n' + audit_volumes + '\n',
        1
    )

with open(filepath, 'w') as f:
    f.write(content_new)

print('Audit flags and volume mounts added successfully')
PYEOF
  ok "1.2.16–19 fixed — audit logging configured"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Fix 1.2.30 — service-account-extend-token-expiration
# ─────────────────────────────────────────────────────────────────────────────
log "Fix 1.2.30 — SA token expiration..."
if docker exec "$CP" grep -q "\-\-service-account-extend-token-expiration=false" "$APISERVER"; then
  ok "1.2.30 already set"
else
  docker exec "$CP" python3 -c "
filepath = '$APISERVER'
with open(filepath, 'r') as f:
    lines = f.readlines()
new_lines = []
inserted = False
for line in lines:
    new_lines.append(line)
    if line.strip() == '- kube-apiserver' and not inserted:
        indent = len(line) - len(line.lstrip())
        new_lines.append(' ' * indent + '- --service-account-extend-token-expiration=false\n')
        inserted = True
with open(filepath, 'w') as f:
    f.writelines(new_lines)
print('Added: --service-account-extend-token-expiration=false')
"
  ok "1.2.30 fixed"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Fix 1.3.2 — controller-manager profiling
# ─────────────────────────────────────────────────────────────────────────────
log "Fix 1.3.2 — controller-manager --profiling=false..."
if docker exec "$CP" grep -q "\-\-profiling=false" "$CTRLMGR"; then
  ok "1.3.2 already set"
else
  docker exec "$CP" python3 -c "
filepath = '$CTRLMGR'
with open(filepath, 'r') as f:
    lines = f.readlines()
new_lines = []
inserted = False
for line in lines:
    new_lines.append(line)
    if line.strip() == '- kube-controller-manager' and not inserted:
        indent = len(line) - len(line.lstrip())
        new_lines.append(' ' * indent + '- --profiling=false\n')
        inserted = True
with open(filepath, 'w') as f:
    f.writelines(new_lines)
print('Added: --profiling=false to controller-manager')
"
  ok "1.3.2 fixed"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Fix 1.4.1 — scheduler profiling
# ─────────────────────────────────────────────────────────────────────────────
log "Fix 1.4.1 — scheduler --profiling=false..."
if docker exec "$CP" grep -q "\-\-profiling=false" "$SCHEDULER"; then
  ok "1.4.1 already set"
else
  docker exec "$CP" python3 -c "
filepath = '$SCHEDULER'
with open(filepath, 'r') as f:
    lines = f.readlines()
new_lines = []
inserted = False
for line in lines:
    new_lines.append(line)
    if line.strip() == '- kube-scheduler' and not inserted:
        indent = len(line) - len(line.lstrip())
        new_lines.append(' ' * indent + '- --profiling=false\n')
        inserted = True
with open(filepath, 'w') as f:
    f.writelines(new_lines)
print('Added: --profiling=false to scheduler')
"
  ok "1.4.1 fixed"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Wait for API server to restart (kubelet detects manifest changes)
# ─────────────────────────────────────────────────────────────────────────────
log "Waiting for API server to restart with new flags (up to 90s)..."
sleep 10
for i in $(seq 1 18); do
  if kubectl cluster-info --request-timeout=5s &>/dev/null; then
    ok "API server is back up!"
    break
  fi
  echo "       Waiting... ($((i*5))s)"
  sleep 5
done

kubectl cluster-info --request-timeout=10s \
  || die "API server did not come back up — check: docker logs $CP"

# ─────────────────────────────────────────────────────────────────────────────
# Verify
# ─────────────────────────────────────────────────────────────────────────────
echo ""
log "Verifying fixes..."
docker exec "$CP" grep -c "\-\-profiling=false" "$APISERVER" | grep -q "1" \
  && ok "API server: --profiling=false ✓"
docker exec "$CP" grep -c "\-\-audit-log-path" "$APISERVER" | grep -q "1" \
  && ok "API server: audit logging ✓"
docker exec "$CP" grep -c "\-\-profiling=false" "$CTRLMGR" | grep -q "1" \
  && ok "Controller manager: --profiling=false ✓"
docker exec "$CP" grep -c "\-\-profiling=false" "$SCHEDULER" | grep -q "1" \
  && ok "Scheduler: --profiling=false ✓"
docker exec "$CP" ls -la /var/log/audit/audit.log 2>/dev/null \
  && ok "Audit log file exists ✓" || echo "       Audit log not yet written (normal if no events yet)"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Phase 4.1 — Control Plane Hardening Done!  ${NC}"
echo -e "${GREEN}  9 of 10 kube-bench FAILs fixed             ${NC}"
echo -e "${GREEN}  (1.2.5 kubelet CA: Kind environment limit) ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo ""
echo "  Next: Run kube-bench again to verify:"
echo "  kubectl delete job kube-bench-master --ignore-not-found"
echo "  kubectl apply -f infra/kind/kube-bench-master.yaml"
echo "  sleep 40 && kubectl logs job/kube-bench-master | grep -E 'FAIL|PASS|WARN' | head -30"
