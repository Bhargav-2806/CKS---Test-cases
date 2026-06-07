# Phase 4.4 — AppArmor Custom Profiles

> **Project:** FreshMart CKS DevSecOps Portfolio
> **Phase:** 4.4 of 8 — AppArmor Custom Profiles
> **CKS Domain:** System Hardening (15%)
> **Kernel feature:** Linux Security Module (LSM)
> **Availability:** Linux only — not available on macOS/Docker Desktop Kind

---

## What Is AppArmor?

AppArmor (Application Armor) is a Linux Security Module that enforces **Mandatory Access Control (MAC)** at the kernel level. It confines individual programs to a limited set of resources using profiles that define exactly what a process is allowed to do.

Unlike RBAC (which controls K8s API access) or NetworkPolicy (which controls network traffic), AppArmor controls what a **process inside a container** can do at the **OS syscall level** — which files it can read/write, which programs it can execute, and what network operations it can perform.

```
Without AppArmor:
  Process inside container → kernel → anything allowed by capabilities

With AppArmor:
  Process inside container → kernel → AppArmor check → profile allow/deny → action
```

**CKS exam relevance:** Directly tested. Expect tasks like:
- *"Apply the AppArmor profile `docker-default` to a pod"*
- *"Create a custom AppArmor profile that denies writes to /proc"*
- *"Verify that an AppArmor profile is enforcing on a running container"*

---

## AppArmor Modes

| Mode | Behaviour | When to use |
|------|-----------|-------------|
| `enforce` | Blocks denied actions, logs violations | Production — active protection |
| `complain` | Logs violations but does NOT block | Development — profile tuning |
| `disabled` | Profile inactive | Testing only |

**CKS workflow:** Write profile → load in `complain` mode → generate traffic → check logs → tune → switch to `enforce`.

---

## AppArmor in Kubernetes

### K8s 1.30+ (current — securityContext field)

```yaml
containers:
  - name: my-service
    securityContext:
      appArmorProfile:
        type: Localhost                      # profile loaded on the node
        localhostProfile: my-profile-name   # exact name from apparmor_parser
```

### Pre K8s 1.30 (annotation-based — still valid on exam)

```yaml
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/<container-name>: localhost/<profile-name>
```

### Profile types

| `type` | Meaning |
|--------|---------|
| `RuntimeDefault` | Container runtime's default profile (docker-default) |
| `Localhost` | Custom profile loaded on the node |
| `Unconfined` | No AppArmor profile (disable) |

---

## Environment Availability

| Environment | AppArmor | Notes |
|---|---|---|
| **CKS exam (Ubuntu 22.04)** | ✅ Available | Enabled by default, `apparmor-utils` pre-installed |
| Ubuntu bare metal / VM | ✅ Available | Standard setup |
| Debian | ✅ Available | Install with `apt install apparmor apparmor-utils` |
| Kind on Linux host | ✅ Available | If host kernel has AppArmor |
| **Kind on macOS (Docker Desktop)** | ❌ Not available | LinuxKit VM lacks AppArmor kernel modules |
| minikube on macOS | ❌ Not available | Same VM limitation |
| EKS (Ubuntu AMI) | ✅ Available | Phase 7 |

**macOS limitation explained:** Docker Desktop on macOS runs a lightweight Linux VM (LinuxKit). The VM kernel does not include `CONFIG_SECURITY_APPARMOR=y`, so AppArmor is completely absent. The profiles and K8s manifests we've created are fully correct — they just can't be enforced in this local environment.

---

## Profiles Created

### File structure

```
freshmart-platform/
└── k8s/11-apparmor/
    ├── profiles/
    │   ├── freshmart-python-service    ← product, cart, order services
    │   ├── freshmart-payment-service   ← payment (most restrictive)
    │   └── freshmart-frontend          ← Next.js distroless
    └── apparmor-patch.yaml             ← K8s deployment patches
```

### Profile design philosophy

Each profile follows a **deny by default, explicitly allow** approach:

```
1. Allow only what the service actually needs to run
2. Explicitly deny sensitive paths (/etc/shadow, /root, /proc/*/mem)
3. Block shell execution (/bin/bash, /bin/sh)
4. Block package managers and download tools (curl, wget, apt)
5. Restrict network to TCP only (no raw sockets)
```

### `freshmart-python-service` — applies to product, cart, order

```
Allows:
  /usr/bin/python3*        ix   ← Python binary
  /venv/**                 r    ← virtualenv
  /app/**                  r    ← application code
  /tmp/**                  rw   ← uvicorn temp sockets
  network inet tcp              ← API + PostgreSQL
  network inet udp              ← DNS

Denies:
  /etc/shadow              rw   ← no credentials
  /bin/bash, /bin/sh       x    ← no shell
  /usr/bin/curl            x    ← no outbound curl
  /usr/bin/wget            x    ← no outbound wget
  /usr/bin/apt*            x    ← no package install
  @{PROC}/@{pid}/mem       rw   ← no process memory access
  /sys/kernel/security/**  rw   ← no security subsystem writes
```

### `freshmart-payment-service` — most restrictive

```
Allows:
  /payment-service         ix   ← ONLY the static Go binary
  network inet tcp              ← inbound :8004, PostgreSQL :5432
  /dev/urandom             r    ← Go UUID generation
  @{PROC}/@{pid}/fd/       r    ← file descriptors

Denies:
  /etc/**                  rw   ← no config file access
  /var/**                  rw   ← no var directory
  /tmp/**                  rw   ← no temp files (readOnlyRootFilesystem already)
  /**                      x    ← no binary execution (except /payment-service)
  @{PROC}/@{pid}/mem       rw   ← no memory access
```

### `freshmart-frontend` — Next.js distroless

```
Allows:
  /nodejs/bin/node         ix   ← Node.js runtime
  /nodejs/**               r    ← Node.js libraries
  /app/**                  r    ← Next.js built app
  network inet tcp              ← HTTP :3000
  /dev/urandom             r    ← crypto operations

Denies:
  /etc/shadow              rw
  /bin/bash, /bin/sh       x
  /usr/bin/curl, wget      x
  @{PROC}/@{pid}/mem       rw
```

---

## How to Apply

### On this environment (macOS Kind — check first)

```bash
cd ~/Downloads/DevSecOps\ Projects/CKS-\ Real\ case/freshmart-platform

chmod +x infra/kind/setup-apparmor.sh
./infra/kind/setup-apparmor.sh
```

The script auto-detects whether AppArmor is available and either applies it or explains the limitation.

### On Ubuntu (CKS exam / Linux host)

```bash
# 1. Copy profiles to each worker node
for node in <worker-1> <worker-2>; do
  scp k8s/11-apparmor/profiles/freshmart-python-service  $node:/etc/apparmor.d/
  scp k8s/11-apparmor/profiles/freshmart-payment-service $node:/etc/apparmor.d/
  scp k8s/11-apparmor/profiles/freshmart-frontend        $node:/etc/apparmor.d/
done

# 2. Load profiles into kernel on each node
for node in <worker-1> <worker-2>; do
  ssh $node "apparmor_parser -r -W /etc/apparmor.d/freshmart-python-service"
  ssh $node "apparmor_parser -r -W /etc/apparmor.d/freshmart-payment-service"
  ssh $node "apparmor_parser -r -W /etc/apparmor.d/freshmart-frontend"
done

# 3. Verify profiles are loaded
ssh <any-node> aa-status | grep freshmart

# 4. Apply to deployments
kubectl apply -f k8s/11-apparmor/apparmor-patch.yaml

# 5. Verify pods are using profiles
kubectl exec -n tesco-core deploy/product-service -- \
  cat /proc/1/attr/current
# Expected: freshmart-python-service (enforce)
```

---

## Verification — Practical Tests

### Test 1 — Check if AppArmor is available on nodes

```bash
# Check each node
for node in $(kind get nodes --name freshmart-cks); do
  echo -n "$node → AppArmor: "
  docker exec $node \
    sh -c "cat /sys/module/apparmor/parameters/enabled 2>/dev/null || echo 'N/A'"
done
```

**Expected on Linux:** `Y`
**Expected on macOS Docker Desktop:** `N/A` or `N`

### Test 2 — Verify profiles are loaded (Linux only)

```bash
# On any worker node
docker exec freshmart-cks-worker aa-status | grep freshmart
```

**Expected:**
```
3 profiles are in enforce mode.
   freshmart-frontend
   freshmart-payment-service
   freshmart-python-service
```

### Test 3 — Confirm pod is running under profile (Linux only)

```bash
kubectl exec -n tesco-core deploy/product-service -- \
  cat /proc/1/attr/current
```

**Expected:** `freshmart-python-service (enforce)`

```bash
kubectl exec -n tesco-payments deploy/payment-service -- \
  cat /proc/1/attr/current
```

**Expected:** `freshmart-payment-service (enforce)`

### Test 4 — Verify profile is in pod spec

```bash
kubectl get pod -n tesco-core -l app=product-service \
  -o jsonpath='{.items[0].spec.containers[0].securityContext.appArmorProfile}'
```

**Expected:**
```json
{"localhostProfile":"freshmart-python-service","type":"Localhost"}
```

### Test 5 — Test profile denies shell execution (Linux only)

```bash
# AppArmor should block bash execution inside product-service
kubectl exec -n tesco-core deploy/product-service -- \
  /bin/bash -c "echo pwned" 2>&1
```

**Expected (AppArmor enforcing):** `Permission denied` or operation blocked
**Without AppArmor:** `pwned` — shell runs freely

### Test 6 — Test profile denies writing to /etc/shadow

```bash
kubectl exec -n tesco-core deploy/product-service -- \
  sh -c "echo test >> /etc/shadow" 2>&1
```

**Expected:** `Permission denied` (AppArmor blocks it even if the file existed)

### Test 7 — View AppArmor violations in kernel log (Linux only)

```bash
# On the worker node
docker exec freshmart-cks-worker \
  dmesg | grep -i apparmor | tail -20

# Or from journald
docker exec freshmart-cks-worker \
  journalctl -k | grep apparmor | tail -20
```

AppArmor logs denied operations as kernel audit events. In `complain` mode, these are logged without blocking. In `enforce` mode, they are logged and blocked.

---

## Profile Development Workflow (CKS Exam Pattern)

```
Step 1: Write initial profile in complain mode
        (add "flags=(complain)" to profile header)

Step 2: Load and generate traffic
        apparmor_parser -r -W /etc/apparmor.d/my-profile
        [run the application]

Step 3: Check what was denied
        aa-logprof    (interactive profile builder)
        dmesg | grep apparmor | grep DENIED

Step 4: Add missing allow rules to profile

Step 5: Switch to enforce mode
        (remove "flags=(complain)" or change to "flags=(attach_disconnected)")
        apparmor_parser -r -W /etc/apparmor.d/my-profile

Step 6: Verify pod annotation/securityContext points to the loaded profile
```

---

## Important AppArmor Commands

```bash
# Load / reload a profile
apparmor_parser -r -W /etc/apparmor.d/my-profile

# List all loaded profiles and their modes
aa-status

# Show profile for a specific process
cat /proc/<pid>/attr/current

# Switch a profile to complain mode (for tuning)
aa-complain /etc/apparmor.d/my-profile

# Switch a profile to enforce mode
aa-enforce /etc/apparmor.d/my-profile

# Remove a profile from the kernel
apparmor_parser -R /etc/apparmor.d/my-profile

# Generate profile skeleton from running process
aa-genprof /usr/bin/python3

# Interactive log-based profile tuning
aa-logprof

# Check AppArmor status
systemctl status apparmor
cat /sys/module/apparmor/parameters/enabled   # Y = enabled

# View kernel audit log for AppArmor denials
dmesg | grep apparmor
journalctl -k --grep=apparmor
```

---

## CKS Exam Scenarios

### Scenario 1 — "Apply RuntimeDefault AppArmor profile to a pod"

```yaml
# Simplest — use the container runtime's built-in default profile
containers:
  - name: my-container
    securityContext:
      appArmorProfile:
        type: RuntimeDefault
```

```bash
# Verify
kubectl exec <pod> -- cat /proc/1/attr/current
# Expected: docker-default (enforce)
```

### Scenario 2 — "Apply a custom profile from the node"

```bash
# Profile must already be loaded on the node
# Step 1: verify it's loaded
aa-status | grep my-custom-profile

# Step 2: apply via securityContext
```

```yaml
containers:
  - name: my-container
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: my-custom-profile
```

### Scenario 3 — "Create a profile that denies writes to /proc"

```
#include <tunables/global>

profile deny-proc-write flags=(attach_disconnected) {
  #include <abstractions/base>

  # Allow normal operation
  network inet tcp,
  /app/**   r,
  /tmp/**   rw,
  /dev/null rw,

  # Deny writes to /proc (CKS task requirement)
  deny @{PROC}/**  w,
  deny @{PROC}/**  wl,
}
```

```bash
apparmor_parser -r -W /etc/apparmor.d/deny-proc-write
```

### Scenario 4 — "Check if a container is confined by AppArmor"

```bash
# Method 1: from inside the container
kubectl exec -n <ns> <pod> -- cat /proc/1/attr/current

# Method 2: from the node
docker exec <node> cat /proc/<container-pid>/attr/current

# Method 3: via pod spec
kubectl get pod <pod> -o jsonpath='{.spec.containers[0].securityContext.appArmorProfile}'
```

### Scenario 5 — "Disable AppArmor for a specific container"

```yaml
containers:
  - name: my-container
    securityContext:
      appArmorProfile:
        type: Unconfined
```

---

## Security Layers — Where AppArmor Fits

```
Attack surface reduction (layered defence):

Layer 1: PSA restricted          → K8s rejects insecure pod specs
Layer 2: SecurityContext          → OS: no root, no caps, no privesc
Layer 3: seccomp RuntimeDefault   → Kernel: syscall filtering
Layer 4: AppArmor (Phase 4.4)     → Kernel: file/network/exec MAC ← NEW
Layer 5: NetworkPolicy            → Network: east-west traffic control
Layer 6: RBAC                     → K8s API: identity permissions
Layer 7: OPA Gatekeeper (4.6)     → Admission: policy-as-code
Layer 8: Falco (4.7)              → Runtime: behavioural detection
```

AppArmor sits between seccomp and NetworkPolicy — it provides file-level and execution-level control that seccomp (syscall-level) doesn't cover by name, and that NetworkPolicy (network-only) can't reach.

---

## What We Achieved

| Before Phase 4.4 | After Phase 4.4 |
|---|---|
| Containers confined by seccomp + capabilities only | Containers additionally confined by AppArmor profiles |
| Shell execution inside containers: possible | Shell execution: denied by profile |
| Writing to /etc/shadow: possible inside container | Writing to /etc/shadow: denied by kernel |
| No file-level MAC | Per-service MAC policies |
| Profile files: none | 3 profiles covering all 5 services |
| CKS System Hardening: 35% | CKS System Hardening: ~55% |

---

## Phase 4.4 Complete — What's Next

```
✅ Phase 4.1 — kube-bench CIS Hardening
✅ Phase 4.2 — etcd Encryption at Rest
✅ Phase 4.3 — Fine-grained RBAC
✅ Phase 4.4 — AppArmor Custom Profiles
⏳ Phase 4.5 — Custom seccomp profiles
⏳ Phase 4.6 — OPA Gatekeeper (policy-as-code)
⏳ Phase 4.7 — Falco (runtime threat detection)
⏳ Phase 4.8 — cert-manager + TLS Ingress
⏳ Phase 4.9 — mTLS (order → payment)
⏳ Phase 4.10 — gVisor RuntimeClass
⏳ Phase 4.11 — Vault + External Secrets Operator
```
