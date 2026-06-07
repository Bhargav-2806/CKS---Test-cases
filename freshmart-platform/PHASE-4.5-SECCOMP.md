# Phase 4.5 — Custom seccomp Profiles

> **Project:** FreshMart CKS DevSecOps Portfolio
> **Phase:** 4.5 of 8 — Custom seccomp Profiles
> **CKS Domain:** System Hardening (15%)
> **Kernel feature:** Linux seccomp (Secure Computing Mode)
> **Availability:** ✅ Works on macOS + Kind (Docker Desktop supports it)

---

## What Is seccomp?

seccomp (Secure Computing Mode) is a Linux kernel feature that restricts which **system calls** (syscalls) a process can make. Every interaction between a program and the kernel goes through a syscall — file reads, network connections, memory allocation, process creation. seccomp intercepts syscalls before they reach the kernel and allows or denies them based on a profile.

```
Without seccomp:
  Container process ──syscall──► kernel  (unrestricted)

With RuntimeDefault:
  Container process ──syscall──► seccomp filter ──► kernel
                                 (blocks ~40 dangerous syscalls)

With custom Localhost profile (Phase 4.5):
  Container process ──syscall──► seccomp filter ──► kernel
                                 (blocks ALL except explicit allowlist)
                                 (KILL_PROCESS on ptrace/kexec/etc.)
```

**CKS exam relevance:**
- "Apply `RuntimeDefault` seccomp to a pod" (already done in Phase 3)
- "Apply a custom seccomp profile from the node filesystem"
- "Verify seccomp is active on a running container"
- Understand the difference between `RuntimeDefault`, `Localhost`, and `Unconfined`

---

## seccomp vs AppArmor vs Capabilities

| Control | What it restricts | Layer |
|---|---|---|
| **Capabilities** | Coarse kernel privileges (NET_RAW, SYS_ADMIN, etc.) | Kernel |
| **seccomp** | Individual syscalls (read, write, ptrace, kexec...) | Kernel |
| **AppArmor** | Files, network, binary execution by path | Kernel LSM |
| **NetworkPolicy** | Pod-to-pod network traffic | iptables |
| **RBAC** | Kubernetes API operations | API server |

seccomp operates at the most granular kernel level — it intercepts the actual system call numbers before any file path or permission check.

---

## Phase 3 vs Phase 4.5

| Phase 3 | Phase 4.5 |
|---|---|
| `seccompProfile.type: RuntimeDefault` | `seccompProfile.type: Localhost` |
| Container runtime's built-in profile | Custom profile per service |
| Blocks ~40 dangerous syscalls | Blocks ALL except explicit allowlist |
| Same for every container | Tailored to each service's actual needs |
| `SCMP_ACT_ERRNO` on denied calls | `SCMP_ACT_KILL_PROCESS` on most dangerous |

---

## seccomp Actions (CKS Reference)

| Action | What happens | When to use |
|---|---|---|
| `SCMP_ACT_ALLOW` | Syscall proceeds normally | Allowed syscalls |
| `SCMP_ACT_ERRNO` | Returns `EPERM` to process | Default deny |
| `SCMP_ACT_KILL_PROCESS` | Kills process immediately | Critical dangerous syscalls |
| `SCMP_ACT_KILL_THREAD` | Kills calling thread | Less aggressive than KILL_PROCESS |
| `SCMP_ACT_LOG` | Logs but allows | Profile development/audit |
| `SCMP_ACT_TRACE` | Notifies tracer | Debug/strace integration |

---

## Profiles Created

### File structure

```
freshmart-platform/
└── k8s/12-seccomp/profiles/
    ├── freshmart-python.json    ← product, cart, order services
    ├── freshmart-payment.json   ← payment service (most restrictive)
    └── freshmart-frontend.json  ← Next.js frontend
```

### Profile architecture

All profiles use:
```json
{
  "defaultAction": "SCMP_ACT_ERRNO",   ← deny ALL syscalls not in list
  "syscalls": [
    { "names": ["ptrace","kexec_load",...], "action": "SCMP_ACT_KILL_PROCESS" },
    { "names": ["read","write",...],        "action": "SCMP_ACT_ALLOW" }
  ]
}
```

### What each profile blocks beyond RuntimeDefault

| Syscall | Risk | Action |
|---|---|---|
| `ptrace` | Process inspection / debugging (attacker tool) | `KILL_PROCESS` |
| `process_vm_readv/writev` | Cross-process memory read/write | `KILL_PROCESS` |
| `kexec_load` / `kexec_file_load` | Load a new kernel | `KILL_PROCESS` |
| `init_module` / `finit_module` | Load kernel module | `KILL_PROCESS` |
| `delete_module` | Remove kernel module | `KILL_PROCESS` |
| `reboot` | System reboot | `KILL_PROCESS` |
| `acct` | Process accounting | `KILL_PROCESS` |
| `mount` / `umount2` (payment) | Filesystem mounting | `KILL_PROCESS` |
| `chroot` / `pivot_root` (payment) | Container escape vectors | `KILL_PROCESS` |

### Profile size comparison

| Profile | Allowed syscalls | Profile approach |
|---|---|---|
| `Unconfined` | All (~400+) | No filtering |
| `RuntimeDefault` | ~350 (denies ~40) | Denylist |
| `freshmart-python.json` | ~120 | Allowlist |
| `freshmart-payment.json` | ~60 | Tight allowlist |
| `freshmart-frontend.json` | ~130 | Allowlist |

---

## How to Apply

```bash
cd ~/Downloads/DevSecOps\ Projects/CKS-\ Real\ case/freshmart-platform

# Step 1: Load profiles onto nodes + patch deployments
chmod +x infra/kind/setup-seccomp.sh
./infra/kind/setup-seccomp.sh

# Step 2: Verify everything
chmod +x infra/kind/verify-seccomp.sh
./infra/kind/verify-seccomp.sh
```

### What setup-seccomp.sh does

```
1. Creates /var/lib/kubelet/seccomp/freshmart/ on EVERY Kind node
2. Copies the 3 JSON profiles to each node via docker cp
3. Patches all 5 deployments: seccompProfile.type RuntimeDefault → Localhost
4. Waits for rollouts
5. Smoke tests API endpoints still respond
```

---

## Verification — Practical Tests

### Test 1 — Profile files on nodes

```bash
# List profiles on a worker node
docker exec freshmart-cks-worker \
  ls -la /var/lib/kubelet/seccomp/freshmart/
```

**Expected:**
```
-rw-r--r-- freshmart-frontend.json
-rw-r--r-- freshmart-payment.json
-rw-r--r-- freshmart-python.json
```

---

### Test 2 — Pod spec shows Localhost profile

```bash
kubectl get pod -n tesco-core -l app=product-service \
  -o jsonpath='{.items[0].spec.securityContext.seccompProfile}'
```

**Expected:**
```json
{"localhostProfile":"freshmart/freshmart-python.json","type":"Localhost"}
```

---

### Test 3 — seccomp is active at process level (mode=2)

```bash
# /proc/1/status shows seccomp mode:
# 0 = disabled, 1 = strict, 2 = filter (our custom profile)
kubectl exec -n tesco-core deploy/product-service -- \
  grep Seccomp /proc/1/status
```

**Expected:** `Seccomp:	2`

Mode `2` means seccomp BPF filter is active — our custom JSON profile is enforcing.

```bash
# Also works for payment-service
kubectl exec -n tesco-payments deploy/payment-service -- \
  grep Seccomp /proc/1/status
```

---

### Test 4 — ptrace is blocked (KILL_PROCESS)

```bash
# Try to call ptrace from inside product-service
# Our profile has ptrace: SCMP_ACT_KILL_PROCESS
kubectl exec -n tesco-core deploy/product-service -- \
  python3 -c "
import ctypes, sys
libc = ctypes.CDLL(None, use_errno=True)
ret = libc.syscall(101, 0, 0, 0, 0)  # syscall 101 = ptrace, PTRACE_TRACEME=0
err = ctypes.get_errno()
print(f'ptrace returned: ret={ret} errno={err}')
" 2>&1
```

**Expected:** Process killed or `Bad system call` — ptrace is `SCMP_ACT_KILL_PROCESS`.

---

### Test 5 — Verify via /proc/1/status (alternative to exec)

```bash
# Get PID 1's seccomp status without kubectl exec
POD=$(kubectl get pods -n tesco-core -l app=product-service \
  --no-headers -o custom-columns="N:.metadata.name" | head -1)

kubectl get pod $POD -n tesco-core \
  -o jsonpath='{.spec.securityContext.seccompProfile.type}'
# Expected: Localhost

kubectl get pod $POD -n tesco-core \
  -o jsonpath='{.spec.securityContext.seccompProfile.localhostProfile}'
# Expected: freshmart/freshmart-python.json
```

---

### Test 6 — API still works (profile not breaking service)

```bash
# Products API
curl -s http://localhost/api/products | python3 -m json.tool | head -5
# Expected: JSON with product data

# Cart API
curl -s -X POST http://localhost/api/cart/seccomp-verify/items \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "quantity": 1}' | python3 -m json.tool
# Expected: cart item response
```

---

### Test 7 — Run full automated verification

```bash
./infra/kind/verify-seccomp.sh
```

**Expected output:**
```
── Test 1 — Profile files exist on all nodes ──────────────
  ✅ PASS  freshmart-cks-worker: freshmart-python.json present
  ✅ PASS  freshmart-cks-worker: freshmart-payment.json present
  ✅ PASS  freshmart-cks-worker: freshmart-frontend.json present
  ... (×3 nodes)

── Test 2 — Pod specs use Localhost seccomp profiles ──────
  ✅ PASS  tesco-core/product-service → Localhost/freshmart/freshmart-python.json
  ✅ PASS  tesco-payments/payment-service → Localhost/freshmart/freshmart-payment.json
  ...

── Test 3 — All pods Running with custom seccomp ──────────
  ✅ PASS  tesco-core/product-service: Running ✓
  ...

── Test 4 — APIs working under custom seccomp ─────────────
  ✅ PASS  Products API: HTTP 200 ✓
  ✅ PASS  Cart API: HTTP 200 ✓

── Test 5 — Verify seccomp active at process level ────────
  ✅ PASS  tesco-core/product-service: Seccomp mode=2 (filter/custom) ✓
  ✅ PASS  tesco-payments/payment-service: Seccomp mode=2 (filter/custom) ✓

── Test 6 — Dangerous syscall blocked ─────────────────────
  ✅ PASS  product-service: ptrace blocked ✓

── Test 7 — Profile JSON syntax valid ─────────────────────
  ✅ PASS  freshmart-python.json: valid JSON
  ✅ PASS  freshmart-payment.json: valid JSON
  ✅ PASS  freshmart-frontend.json: valid JSON

Results: 20 passed  |  0 failed  |  0 warnings
```

---

## Important seccomp Commands

```bash
# Check seccomp mode of a process
grep Seccomp /proc/<pid>/status
# 0=disabled, 1=strict, 2=filter (what we want)

# Check if seccomp is supported by the kernel
grep CONFIG_SECCOMP /boot/config-$(uname -r)

# View syscalls made by a process (for profile development)
strace -c python3 -m uvicorn app.main:app 2>&1 | head -20

# Validate a seccomp profile JSON
python3 -c "import json; json.load(open('profile.json')); print('valid')"

# Copy profile to Kind node
docker cp profile.json <node>:/var/lib/kubelet/seccomp/myprofile.json

# Apply RuntimeDefault (simplest)
kubectl patch deploy myapp --type=json -p='[{
  "op":"replace",
  "path":"/spec/template/spec/securityContext/seccompProfile",
  "value":{"type":"RuntimeDefault"}
}]'

# Apply custom Localhost profile
kubectl patch deploy myapp --type=json -p='[{
  "op":"replace",
  "path":"/spec/template/spec/securityContext/seccompProfile",
  "value":{"type":"Localhost","localhostProfile":"myprofile.json"}
}]'
```

---

## Profile Development Workflow (real world)

On a real Ubuntu node, use `strace` to discover what syscalls your service actually needs:

```bash
# 1. Run service under strace to capture syscalls
strace -f -e trace=all -o /tmp/syscalls.log \
  python3 -m uvicorn app.main:app &

# Generate some traffic
curl http://localhost:8001/api/products
curl -X POST http://localhost:8001/api/products/1

# 2. Kill service
kill %1

# 3. Extract unique syscall names
awk -F'(' '{print $1}' /tmp/syscalls.log | sort -u | grep -v '^---\|^+++\|^[0-9]'

# 4. Start with LOG mode profile to catch missing syscalls
# defaultAction: SCMP_ACT_LOG  ← logs but doesn't block

# 5. Check kernel log for logged syscalls
dmesg | grep seccomp

# 6. Switch to ERRNO once profile is stable
# defaultAction: SCMP_ACT_ERRNO

# 7. Switch KILL_PROCESS on most dangerous (ptrace, kexec, etc.)
```

---

## EKS / kubeadm Real-World Differences

### kubeadm on Ubuntu EC2 (CKS exam environment)

**Identical to our Kind setup** — same kubelet, same `/var/lib/kubelet/seccomp/` path, same JSON format. The only difference is you `scp` profiles to EC2 nodes instead of `docker cp` to Kind containers.

```bash
# On kubeadm EC2 cluster
scp k8s/12-seccomp/profiles/freshmart-python.json \
  ubuntu@<node>:/var/lib/kubelet/seccomp/freshmart/
# Then apply the same kubectl patch commands
```

### EKS on AWS

```bash
# EKS with managed node groups — workers are EC2
# Profiles go to the same path on EC2 worker nodes

# Option 1: User data script loads profiles on node bootstrap
# Option 2: DaemonSet copies profiles on startup
# Option 3: Security Profiles Operator (production best practice)
```

**Security Profiles Operator (production EKS approach):**
```yaml
# Profile stored as a Kubernetes CRD — no node SSH needed
apiVersion: security-profiles-operator.x-k8s.io/v1beta1
kind: SeccompProfile
metadata:
  name: freshmart-python
  namespace: tesco-core
spec:
  defaultAction: SCMP_ACT_ERRNO
  syscalls:
    - action: SCMP_ACT_ALLOW
      names: [read, write, openat, close, ...]
    - action: SCMP_ACT_KILL_PROCESS
      names: [ptrace, kexec_load, ...]
```

```yaml
# Pod references it automatically
securityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: operator/tesco-core/freshmart-python.json
```

---

## CKS Exam Scenarios

### Scenario 1 — "Apply RuntimeDefault seccomp to a pod"

```yaml
# Add to pod spec (simplest — already done in Phase 3)
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
```

```bash
# Verify
kubectl exec <pod> -- grep Seccomp /proc/1/status  # 2
```

### Scenario 2 — "Apply custom seccomp profile from node"

```bash
# Step 1: Profile must exist on the node
ls /var/lib/kubelet/seccomp/my-profile.json

# Step 2: Apply
kubectl patch deploy myapp --type=json -p='[{
  "op":"add",
  "path":"/spec/template/spec/securityContext/seccompProfile",
  "value":{"type":"Localhost","localhostProfile":"my-profile.json"}
}]'

# Step 3: Verify
kubectl get pod -l app=myapp \
  -o jsonpath='{.items[0].spec.securityContext.seccompProfile}'
```

### Scenario 3 — "Ensure a pod is NOT running with Unconfined seccomp"

```bash
# Check current profile
kubectl get pod <pod> \
  -o jsonpath='{.spec.securityContext.seccompProfile.type}'

# If Unconfined, fix it
kubectl patch deploy myapp --type=json -p='[{
  "op":"replace",
  "path":"/spec/template/spec/securityContext/seccompProfile",
  "value":{"type":"RuntimeDefault"}
}]'
```

### Scenario 4 — "Create a seccomp profile that blocks chmod"

```json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "syscalls": [
    {
      "names": ["chmod", "fchmod", "fchmodat"],
      "action": "SCMP_ACT_ERRNO"
    }
  ]
}
```

**Note:** `defaultAction: SCMP_ACT_ALLOW` = denylist approach (safer for exam, less restrictive). `defaultAction: SCMP_ACT_ERRNO` = allowlist approach (production grade, more work).

---

## Security Layer Recap

```
Phase 3:  seccompProfile: RuntimeDefault   → ~40 syscalls blocked
Phase 4.5: seccompProfile: Localhost       → all except allowlist blocked
                                           → KILL_PROCESS on ptrace/kexec/modules

Combined with other Phase 4 layers:
  PSA restricted     → no root, no caps at K8s level
  SecurityContext    → no escalation, capabilities dropped
  seccomp (custom)   → syscall-level kernel filtering      ← Phase 4.5
  AppArmor           → file/exec MAC                       ← Phase 4.4
  NetworkPolicy      → east-west traffic control
  OPA Gatekeeper     → admission-time policy enforcement   ← Phase 4.6 next
```

---

## What We Achieved

| Before Phase 4.5 | After Phase 4.5 |
|---|---|
| `RuntimeDefault` — generic runtime profile | Custom per-service allowlists |
| ~40 dangerous syscalls blocked | All syscalls blocked except explicit allowlist |
| `SCMP_ACT_ERRNO` on denied (returns error) | `SCMP_ACT_KILL_PROCESS` on ptrace, kexec, module loading |
| Same profile for all containers | Tailored to each service's actual syscall needs |
| payment-service: same as Python services | payment-service: 60-syscall allowlist (vs 120+ for Python) |
| kube-bench 5.6.2: WARN | kube-bench 5.6.2: fully satisfied |

---

## Phase 4.5 Complete — What's Next

```
✅ Phase 4.1 — kube-bench CIS Hardening
✅ Phase 4.2 — etcd Encryption at Rest
✅ Phase 4.3 — Fine-grained RBAC
✅ Phase 4.4 — AppArmor Custom Profiles
✅ Phase 4.5 — Custom seccomp Profiles
⏳ Phase 4.6 — OPA Gatekeeper (policy-as-code)
⏳ Phase 4.7 — Falco (runtime threat detection)
⏳ Phase 4.8 — cert-manager + TLS Ingress
⏳ Phase 4.9 — mTLS (order → payment)
⏳ Phase 4.10 — gVisor RuntimeClass
⏳ Phase 4.11 — Vault + External Secrets Operator
```
