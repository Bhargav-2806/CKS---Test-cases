# Phase 4.10 — gVisor RuntimeClass

**CKS Domain:** Minimize Microservice Vulnerabilities (20%) — container sandboxing  
**Status:** ✅ Complete

---

## What Is gVisor?

gVisor is a **user-space kernel** from Google. When a container runs under gVisor, its system calls never reach the host Linux kernel directly — they are intercepted and handled by gVisor's own kernel implementation written in Go.

```
Without gVisor (standard runc):

  Container process
        │
        │  syscall (open, read, connect, execve...)
        ▼
  Host Linux Kernel   ← container talks DIRECTLY to the kernel
        │              ← if container escapes, it hits the real kernel
        ▼
  Hardware

──────────────────────────────────────────────────────────────

With gVisor (runsc):

  Container process
        │
        │  syscall
        ▼
  gVisor (Sentry)     ← USER-SPACE kernel written in Go
        │              ← intercepts ALL syscalls
        │  limited syscalls only
        ▼
  Host Linux Kernel   ← container CANNOT reach this directly
        │
        ▼
  Hardware
```

**The key property:** Even if an attacker exploits a vulnerability in the container (or in the Go payment binary), they land in gVisor's sandboxed kernel — not the real host kernel. A container escape becomes much harder because there are two kernel layers to break through.

---

## gVisor Architecture — Two Components

```
┌─────────────────────────────────────────────────────────────┐
│  gVisor                                                       │
│                                                               │
│  ┌──────────────────────────────────┐                        │
│  │  Sentry (user-space kernel)       │                        │
│  │  - Handles all container syscalls │                        │
│  │  - Implements Linux ABI in Go     │                        │
│  │  - Isolated per-container         │                        │
│  └──────────────────────────────────┘                        │
│                                                               │
│  ┌──────────────────────────────────┐                        │
│  │  Gofer (file system proxy)        │                        │
│  │  - Handles file I/O on behalf     │                        │
│  │    of the Sentry                  │                        │
│  │  - Runs in a separate process     │                        │
│  └──────────────────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

---

## gVisor Platforms

| Platform | How it works | Performance | Where it runs |
|----------|-------------|-------------|---------------|
| `ptrace` | Uses Linux ptrace to intercept syscalls | Slower (~2x overhead) | Anywhere — VMs, containers, Kind |
| `kvm` | Uses KVM hardware virtualization | Near-native | Bare metal, GCE, EC2 with KVM |
| `systrap` | Direct syscall interception (new) | Best | Linux kernel >= 4.14 |

**We use `ptrace`** on Kind/Docker Desktop — no KVM available in Docker containers. In production on EKS/GKE (EC2 bare metal nodes), switch to `kvm` or `systrap` for better performance.

---

## Kubernetes Integration — RuntimeClass

RuntimeClass is a K8s API resource that maps a name to a container runtime handler:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor       # ← pod uses this name
handler: runsc        # ← containerd handler registered on nodes
```

To use gVisor for a pod, add one line to the pod spec:

```yaml
spec:
  runtimeClassName: gvisor   # ← that's it
  containers:
  - name: payment-service
    ...
```

No other changes needed. The same container image runs — gVisor is purely a runtime layer.

---

## Files Created

```
k8s/16-gvisor/
├── 00-runtimeclass.yaml           ← RuntimeClass: gvisor → handler: runsc
└── 01-payment-gvisor-patch.yaml   ← Deployment patch: runtimeClassName: gvisor

infra/kind/
└── setup-gvisor.sh                ← Install runsc on Kind nodes + apply K8s resources

PHASE-4.10-GVISOR.md               ← This file
```

---

## How to Deploy

```bash
cd ~/Downloads/DevSecOps\ Projects/CKS-\ Real\ case/freshmart-platform

chmod +x infra/kind/setup-gvisor.sh
./infra/kind/setup-gvisor.sh
```

The script:
1. Detects node architecture (x86_64 / aarch64)
2. Downloads `runsc` + `containerd-shim-runsc-v1` onto all 3 Kind nodes
3. Appends the `runsc` runtime handler to containerd config on each node
4. Writes `/etc/runsc.toml` with `platform=ptrace` for Docker Desktop compatibility
5. Restarts containerd
6. Applies `RuntimeClass gvisor`
7. Runs a smoke test pod to confirm gVisor is working
8. Patches payment-service deployment with `runtimeClassName: gvisor`

---

## Manual Testing

### Test 1 — RuntimeClass Exists

```bash
kubectl get runtimeclass

# Expected:
# NAME     HANDLER   AGE
# gvisor   runsc     1m
```

### Test 2 — Verify gVisor Kernel (smoke test pod)

```bash
# Deploy a simple test pod using gVisor
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gvisor-test
  namespace: default
spec:
  runtimeClassName: gvisor
  restartPolicy: Never
  containers:
  - name: test
    image: busybox:1.36
    command: ["sh", "-c", "uname -r && cat /proc/version"]
    resources:
      limits: {cpu: "100m", memory: "64Mi"}
      requests: {cpu: "50m", memory: "32Mi"}
    securityContext:
      runAsNonRoot: true
      runAsUser: 65534
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      seccompProfile:
        type: RuntimeDefault
EOF

kubectl wait pod/gvisor-test --for=condition=Ready --timeout=60s
kubectl logs gvisor-test

# Expected (gVisor fake kernel):
# 4.4.0
# Linux version 4.4.0 #1 SMP Sun Jan 10 15:06:54 PST 2016

# Compare with a regular pod (real kernel):
kubectl run regular-test --image=busybox:1.36 --restart=Never \
  -- sh -c "uname -r"
kubectl logs regular-test
# Real kernel: 5.15.x or 6.x

kubectl delete pod gvisor-test regular-test --ignore-not-found
```

**The key difference:** gVisor pods always report kernel `4.4.0` — that's gVisor's sandboxed kernel version, regardless of the actual host kernel.

### Test 3 — payment-service is Using gVisor

```bash
# Confirm runtimeClassName is set on the pod
kubectl get pod -n tesco-payments -l app=payment-service \
  -o jsonpath='{.items[0].spec.runtimeClassName}'
# Expected: gvisor

# Full pod details
kubectl describe pod -n tesco-payments -l app=payment-service | \
  grep -E "Runtime Class|runtimeClassName"
```

### Test 4 — payment-service Still Works with gVisor

```bash
# Health check
curl -sk https://freshmart.local/api/products | python3 -m json.tool | head -10

# Full checkout — mTLS + gVisor both active
curl -sk -X POST https://freshmart.local/api/orders \
  -H "Content-Type: application/json" \
  -d '{"session_id":"gvisor-test","delivery_address":{"full_name":"gVisor Test","address_line1":"1 Sandbox Lane","city":"London","postcode":"SW1A 1AA"},"payment_details":{"card_number":"4242424242424242","expiry":"12/27","cvv":"123"}}' \
  | python3 -m json.tool
```

### Test 5 — Verify Syscall Isolation

```bash
# In a gVisor pod, /proc/version shows gVisor's kernel
PAYMENT_POD=$(kubectl get pod -n tesco-payments -l app=payment-service \
  -o jsonpath='{.items[0].metadata.name}')

# Note: payment-service is distroless — no shell, but we can check from node
docker exec freshmart-cks-worker crictl ps | grep payment-service
# Shows the container ID

# Check runtime type
docker exec freshmart-cks-worker bash -c "
  CONTAINER_ID=\$(crictl ps | grep payment-service | awk '{print \$1}')
  crictl inspect \$CONTAINER_ID | python3 -c \"
import json,sys
d=json.load(sys.stdin)
print('Runtime:', d.get('info',{}).get('runtimeType','unknown'))
\"
"
# Expected: Runtime: io.containerd.runsc.v1
```

### Test 6 — Compare Runtimes Side by Side

```bash
# Test pod with gVisor (fake kernel)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gvisor-kernel
  namespace: default
spec:
  runtimeClassName: gvisor
  restartPolicy: Never
  containers:
  - name: t
    image: busybox:1.36
    command: ["sh", "-c", "echo gVisor kernel: \$(uname -r)"]
    resources: {limits: {cpu: "50m", memory: "32Mi"}}
    securityContext: {runAsNonRoot: true, runAsUser: 65534, allowPrivilegeEscalation: false}
EOF

# Test pod with standard runc (real kernel)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: runc-kernel
  namespace: default
spec:
  restartPolicy: Never
  containers:
  - name: t
    image: busybox:1.36
    command: ["sh", "-c", "echo runc kernel: \$(uname -r)"]
    resources: {limits: {cpu: "50m", memory: "32Mi"}}
    securityContext: {runAsNonRoot: true, runAsUser: 65534, allowPrivilegeEscalation: false}
EOF

sleep 5
kubectl logs gvisor-kernel
# Output: gVisor kernel: 4.4.0

kubectl logs runc-kernel
# Output: runc kernel: 5.15.x (real host kernel)

kubectl delete pod gvisor-kernel runc-kernel --ignore-not-found
```

---

## gVisor Syscall Coverage

gVisor implements ~340 of Linux's ~400 system calls. The missing ones are:
- `kexec_load` — reboot into a new kernel (not needed, dangerous)
- `perf_event_open` — performance profiling (potential side-channel)
- `process_vm_readv/writev` — cross-process memory access (privilege escalation vector)
- Some ioctl variants for hardware devices

For standard web services (HTTP server + PostgreSQL client + file I/O), gVisor is 100% compatible. The Go payment binary uses only standard syscalls.

---

## CKS Exam Scenarios

### Scenario 1: "Create a RuntimeClass for gVisor and apply it to a pod"

```bash
# Step 1: Create RuntimeClass
cat <<EOF | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
EOF

# Step 2: Apply to pod (edit existing or create new)
kubectl edit pod <pod-name>
# Add under spec:
#   runtimeClassName: gvisor

# Or patch a deployment:
kubectl patch deployment <name> -n <ns> \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/runtimeClassName","value":"gvisor"}]'
```

### Scenario 2: "Verify a pod is using gVisor"

```bash
# Check spec
kubectl get pod <name> -o jsonpath='{.spec.runtimeClassName}'

# Confirm from inside (if pod has shell)
kubectl exec <pod> -- uname -r
# gVisor: 4.4.0
```

### Scenario 3: "Configure containerd to use gVisor"

The containerd config block (in `/etc/containerd/config.toml`):
```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
```

After editing, restart containerd: `systemctl restart containerd`

---

## gVisor in Real Production

### Who Uses gVisor

| Company | Use case |
|---------|---------|
| **Google Cloud** | GKE Sandbox — optional sandbox for tenant workloads |
| **Cloudflare** | Isolates untrusted customer code |
| **GitHub** | Code execution for GitHub Actions |
| **StackOverflow** | Code execution sandbox |

### When to Use gVisor

**Yes:**
- Running untrusted code (user-submitted scripts, CI pipelines)
- Payment processing, secret handling (extra isolation layer)
- Multi-tenant environments (one customer's container can't escape to another's kernel)

**No:**
- High-performance workloads (database engines, real-time processing) — ptrace overhead
- Pods that need direct hardware access
- Services with heavy syscall usage (might hit unsupported syscalls)

### gVisor vs Other Sandboxes

| Technology | Isolation level | Performance | K8s support |
|-----------|----------------|-------------|-------------|
| **gVisor** | Intercepts all syscalls | ~20-30% overhead (ptrace), ~5% (kvm) | RuntimeClass |
| **Kata Containers** | Full VM per pod | ~10-15% overhead | RuntimeClass |
| **seccomp** | Filter specific syscalls | Minimal overhead | Built-in |
| **AppArmor** | Restrict capabilities/paths | Minimal overhead | Built-in |
| **runc** (default) | No sandboxing | Zero overhead | Default |

**Defence in depth:**
```
Our payment-service stack:
  seccomp (Phase 4.5)   → blocks specific dangerous syscalls
  AppArmor (Phase 4.4)  → restricts file/network access patterns
  gVisor (Phase 4.10)   → intercepts ALL syscalls at user-space kernel
```

All three layers are independent. An attacker must bypass all three.

---

## Important Note on Kind Compatibility

gVisor on Kind works well but has one caveat: the `ptrace` platform is slower than production `kvm`. In production:

```bash
# Production runsc.toml (EC2/GCE with KVM):
[runsc_config]
  platform = "kvm"    # or "systrap" for newer kernels

# Our Kind runsc.toml (Docker Desktop, no KVM):
[runsc_config]
  platform = "ptrace"
```

On EKS (Phase 7), replace `ptrace` with `systrap` (the recommended platform for modern kernels >= 5.4).

---

## Phase Progress

```
✅ Phase 4.1  — kube-bench CIS Hardening
✅ Phase 4.2  — etcd Encryption at Rest
✅ Phase 4.3  — Fine-grained RBAC
✅ Phase 4.4  — AppArmor Custom Profiles
✅ Phase 4.5  — Custom seccomp Profiles
✅ Phase 4.6  — OPA Gatekeeper
⏳ Phase 4.7  — Falco (deploy on EKS in Phase 7)
✅ Phase 4.8  — cert-manager + TLS Ingress
✅ Phase 4.9  — mTLS order → payment
✅ Phase 4.10 — gVisor RuntimeClass (this phase)
⏳ Phase 4.11 — Vault + External Secrets Operator
```
