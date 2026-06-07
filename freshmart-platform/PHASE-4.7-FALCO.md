# Phase 4.7 — Falco Runtime Threat Detection

**CKS Domain:** Monitoring, Logging & Runtime Security (20%)  
**Status:** ✅ Complete

---

## What Is Falco?

Falco is a **runtime security tool** — it watches what's happening inside your containers right now, at the kernel system call level, and fires alerts when something looks wrong.

The key distinction from everything we've built so far:

| Layer | Tool | When it acts | What it catches |
|-------|------|-------------|----------------|
| Build time | Trivy | At CI build | Vulnerable packages in images |
| Admission time | OPA Gatekeeper | At kubectl apply | Bad configuration before pod starts |
| **Runtime** | **Falco** | **While pod is running** | **Actual attacks happening live** |

An attacker who somehow bypasses Gatekeeper and gets a pod running still has to **do something** — open a shell, read a file, make a network call. Falco catches those actions.

---

## How Falco Works

```
┌─────────────────────────────────────────────────────────────────┐
│  Linux Kernel                                                    │
│                                                                  │
│   Container Process  ──syscall──►  kernel                       │
│   (e.g. /bin/sh)                      │                         │
│                                       │  eBPF hook              │
│                                       ▼                         │
│                                  Falco driver                   │
│                                  (modern_ebpf)                  │
└───────────────────────────────────────┬─────────────────────────┘
                                        │
                                        ▼
                              Falco userspace daemon
                                        │
                              Rule evaluation (Rego-like)
                                        │
                    ┌───────────────────┼──────────────────────┐
                    ▼                   ▼                      ▼
              stdout log           gRPC stream           sidekick
          (kubectl logs)        (falco-exporter)    (Slack/Loki/PD)
```

Falco uses **eBPF** (modern_ebpf driver) to hook into the kernel's system call table. Every `execve` (process spawn), `open` (file read/write), `connect` (network), `setuid` (privilege change) passes through Falco's rule engine before completing.

---

## Driver Comparison

| Driver | How it works | Pros | Cons |
|--------|-------------|------|------|
| `kmod` | Kernel module loaded into kernel | Widest syscall coverage | Needs kernel headers, modifies kernel, risky in prod |
| `ebpf` | Classic eBPF program | Safer than kmod | Needs kernel headers to compile |
| `modern_ebpf` | CO-RE eBPF (no kernel headers) | No compilation, portable, safe | Requires kernel >= 5.8 |

**We use `modern_ebpf`** — works on Docker Desktop (macOS) and all modern cloud kernels (EKS, GKE, AKS all use >= 5.10).

---

## Falco Rule Anatomy

```yaml
- rule: FreshMart Shell Spawned in Container
  desc: >
    Why this rule exists — what threat it detects.
  condition: >
    spawned_process and          # syscall: execve
    container and                # only in containers (not host)
    k8s.ns.name = "tesco-core"  # scoped to our namespace
    proc.name in (sh, bash)      # the thing that fired
  output: >
    Human-readable alert with field substitutions:
    (user=%user.name pod=%k8s.pod.name proc=%proc.name)
  priority: CRITICAL             # DEBUG/INFO/WARNING/ERROR/CRITICAL
  tags: [freshmart, cks, shell]  # for filtering/routing
```

### Key Falco Fields

| Field | Meaning | Example |
|-------|---------|---------|
| `proc.name` | Process name | `sh`, `curl`, `python3` |
| `proc.cmdline` | Full command | `sh -c "curl attacker.com"` |
| `proc.pname` | Parent process name | `runc`, `containerd` |
| `proc.is_suid_exe` | Is setuid binary | `true/false` |
| `container.name` | Container name | `product-service` |
| `container.image.repository` | Image name | `freshmart/product-service` |
| `k8s.ns.name` | Kubernetes namespace | `tesco-payments` |
| `k8s.pod.name` | Pod name | `payment-service-7d6c8d-xxx` |
| `fd.name` | File/socket path | `/etc/shadow`, `10.0.0.5:5432` |
| `fd.rport` | Remote TCP port | `5432`, `443`, `4444` |
| `user.name` | Linux username | `root`, `nonroot` |

### Built-in Macros (reusable conditions)

| Macro | Expands to |
|-------|-----------|
| `spawned_process` | `evt.type = execve and evt.dir = <` |
| `container` | `container.id != host` |
| `open_read` | `evt.type in (open, openat) and evt.is_open_read = true` |
| `open_write` | `evt.type in (open, openat) and evt.is_open_write = true` |
| `outbound` | `evt.type in (connect, sendto) and evt.dir = <` |
| `shell_procs` | `proc.name in (sh, bash, zsh, dash, ...)` |

---

## Custom Rules — What We Built

### 10 FreshMart Rules

| # | Rule | Priority | What it catches |
|---|------|----------|----------------|
| 1 | Shell Spawned in Container | CRITICAL | Any shell exec in tesco-core/payments/frontend |
| 2 | Unexpected Process in Payment Service | CRITICAL | ANY process except `/payment-service` in tesco-payments |
| 3 | Sensitive File Read | WARNING | `/etc/shadow`, `/etc/passwd`, SSH keys |
| 4 | Write in Immutable Payment Container | ERROR | Any write to readOnlyRootFilesystem (non-/tmp) |
| 5 | Package Manager Executed | ERROR | `apt`, `pip`, `npm`, `curl` installs in container |
| 6 | Payment Service Unexpected Outbound | CRITICAL | Any port other than 5432 from payment-service |
| 7 | Privilege Escalation Attempt | CRITICAL | setuid binary execution |
| 8 | Container Drift Detected | CRITICAL | Executable not in original image is run |
| 9 | /proc Filesystem Recon | WARNING | Reading `/proc/1/environ`, `/proc/1/cmdline` |
| 10 | Core Service Unexpected Port | WARNING | Outbound to unexpected port from tesco-core |

---

## Files Created

```
security/falco/
├── falco-values.yaml           ← Helm values (modern_ebpf, JSON output, custom rules)
└── rules/
    └── freshmart-rules.yaml    ← 10 custom rules with lists, macros, and rules

infra/kind/
└── setup-falco.sh              ← Helm install script

PHASE-4.7-FALCO.md              ← This file
```

---

## How to Install

```bash
cd ~/Downloads/DevSecOps\ Projects/CKS-\ Real\ case/freshmart-platform

chmod +x infra/kind/setup-falco.sh
./infra/kind/setup-falco.sh
```

The script:
1. Checks Kind cluster is running
2. Verifies kernel version supports modern_ebpf
3. Adds falcosecurity Helm repo
4. Creates `falco` namespace (PSA: privileged — Falco needs kernel access)
5. Installs Falco with FreshMart custom rules via `--set-file`
6. Waits for DaemonSet ready on all nodes
7. Verifies custom rules are loaded

---

## Manual Testing — Trigger and Observe Alerts

### Setup: Watch Falco logs in a dedicated terminal

Open a **second terminal** and run this before triggering alerts:

```bash
# Watch Falco alerts in real time (JSON formatted)
kubectl logs -n falco -l app.kubernetes.io/name=falco -f \
  | grep -E "FreshMart|CRITICAL|WARNING|ERROR" \
  | python3 -m json.tool 2>/dev/null || \
  kubectl logs -n falco -l app.kubernetes.io/name=falco -f
```

Keep this running. Now trigger alerts in your main terminal:

---

### Test 1 — Shell in Container (CRITICAL)

**What it simulates:** An attacker uses `kubectl exec` to get an interactive shell.

```bash
# Get a product-service pod name
POD=$(kubectl get pod -n tesco-core -l app=product-service \
  -o jsonpath='{.items[0].metadata.name}')

# Exec a shell — this is the attack action
kubectl exec -it $POD -n tesco-core -- /bin/sh
```

Inside the shell, type `exit` to quit. In the Falco terminal you'll see:

```json
{
  "priority": "Critical",
  "rule": "FreshMart Shell Spawned in Container",
  "output": "SHELL SPAWNED IN FRESHMART CONTAINER (user=nonroot shell=sh parent=runc cmdline=sh pod=product-service-xxx ns=tesco-core image=freshmart/product-service)"
}
```

---

### Test 2 — Read /etc/shadow (WARNING)

**What it simulates:** Attacker inside a container harvesting credentials.

```bash
POD=$(kubectl get pod -n tesco-core -l app=product-service \
  -o jsonpath='{.items[0].metadata.name}')

# Exec into pod and try to read shadow file
kubectl exec -it $POD -n tesco-core -- \
  sh -c "cat /etc/shadow 2>/dev/null || echo 'file not readable'"
```

Falco fires:
```json
{
  "priority": "Warning",
  "rule": "FreshMart Sensitive File Read",
  "output": "SENSITIVE FILE READ IN CONTAINER (user=nonroot file=/etc/shadow proc=cat pod=product-service-xxx ns=tesco-core)"
}
```

---

### Test 3 — Package Manager in Container (ERROR)

**What it simulates:** Attacker installs tools (netcat, curl) post-compromise.

```bash
POD=$(kubectl get pod -n tesco-core -l app=cart-service \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $POD -n tesco-core -- \
  sh -c "pip3 install requests 2>&1 | head -5 || true"
```

Falco fires:
```json
{
  "priority": "Error",
  "rule": "FreshMart Package Manager Executed in Container",
  "output": "PACKAGE MANAGER EXECUTED IN CONTAINER (user=nonroot pkg_mgr=pip3 cmdline=pip3 install requests pod=cart-service-xxx)"
}
```

---

### Test 4 — /proc Recon (WARNING)

**What it simulates:** Attacker reading host process environment variables (looking for secrets).

```bash
POD=$(kubectl get pod -n tesco-core -l app=order-service \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $POD -n tesco-core -- \
  sh -c "cat /proc/1/environ 2>/dev/null | tr '\0' '\n' | head -10 || echo 'access denied'"
```

---

### Test 5 — Payment Service (Strictest)

**What it simulates:** Any exec into the payment-service (should NEVER happen — it's distroless).

```bash
# This will FAIL at container level (no shell binary exists in distroless)
# BUT Falco still detects the exec attempt via syscall monitoring
POD=$(kubectl get pod -n tesco-payments -l app=payment-service \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec $POD -n tesco-payments -- /bin/sh 2>&1 || true
# Error: OCI runtime exec failed: ... no such file or directory

# Falco still fires Rule 2 (Unexpected Process in Payment Service)
# because the execve syscall happened before the "not found" error
```

---

### Test 6 — Check All Falco Alerts Summary

```bash
# All alerts in the last 5 minutes
kubectl logs -n falco -l app.kubernetes.io/name=falco \
  --since=5m | grep -c "FreshMart"

# Show only CRITICAL alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco \
  --since=5m | grep "Critical" | jq '.output' 2>/dev/null || \
  kubectl logs -n falco -l app.kubernetes.io/name=falco \
  --since=5m | grep "Critical"

# List all rules that have fired
kubectl logs -n falco -l app.kubernetes.io/name=falco \
  --since=1h | grep '"rule"' | sort | uniq -c | sort -rn
```

---

### Test 7 — Verify Falco Rules are Loaded

```bash
# List all rules Falco knows about (including FreshMart custom ones)
FALCO_POD=$(kubectl get pods -n falco -l app.kubernetes.io/name=falco \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n falco $FALCO_POD -- \
  falco --list 2>/dev/null | grep -i freshmart

# Expected: all 10 FreshMart rules listed
```

---

## Important Falco Commands

```bash
# Watch live alerts (raw)
kubectl logs -n falco -l app.kubernetes.io/name=falco -f

# Watch live alerts (only CRITICAL)
kubectl logs -n falco -l app.kubernetes.io/name=falco -f | grep Critical

# View on a specific node (Falco is a DaemonSet — one pod per node)
kubectl logs -n falco falco-<node-specific-pod> -f

# Check Falco config loaded correctly
kubectl exec -n falco $FALCO_POD -- falco --list

# View loaded rules files
kubectl exec -n falco $FALCO_POD -- ls /etc/falco/rules.d/

# Validate a rule file without applying
falco --validate /path/to/rules.yaml

# Dry-run against a recorded syscall trace
falco -e trace.scap --dry-run

# Check Falco version
kubectl exec -n falco $FALCO_POD -- falco --version
```

---

## CKS Exam Scenarios

### Scenario 1: "Create a Falco rule to detect shell execution in the default namespace"

```yaml
- rule: Shell in Default Namespace
  desc: Shell executed in a container in the default namespace
  condition: >
    spawned_process and
    container and
    k8s.ns.name = "default" and
    proc.name in (sh, bash, dash, zsh)
  output: >
    Shell in default namespace (user=%user.name shell=%proc.name
    pod=%k8s.pod.name cmdline=%proc.cmdline)
  priority: WARNING
  tags: [exam, shell]
```

**Apply it:**
```bash
# Edit Falco's custom rules ConfigMap
kubectl edit configmap falco-rules -n falco
# OR use helm upgrade --set-file ...
```

### Scenario 2: "Configure Falco to alert when a container reads /etc/passwd"

```yaml
- rule: Passwd File Read
  desc: A container is reading /etc/passwd
  condition: >
    open_read and
    container and
    fd.name = /etc/passwd
  output: >
    /etc/passwd read in container (user=%user.name proc=%proc.name pod=%k8s.pod.name)
  priority: WARNING
  tags: [exam]
```

### Scenario 3: "Falco is installed but not alerting — troubleshoot"

```bash
# Check if driver loaded
kubectl logs -n falco $FALCO_POD | grep -i "driver\|ebpf\|loaded"

# Check if rules loaded
kubectl logs -n falco $FALCO_POD | grep -i "rule"

# Check for errors
kubectl logs -n falco $FALCO_POD | grep -i "error\|warn\|fail"

# Verify the syscall source is active
kubectl exec -n falco $FALCO_POD -- falco --list | head -5
```

### Scenario 4: "Where do Falco alerts go in this cluster?"

```bash
# In our cluster: stdout (kubectl logs)
# To check:
kubectl logs -n falco -l app.kubernetes.io/name=falco | tail -20

# In production: Falco Sidekick routes to Slack/Loki/Elasticsearch
# Check sidekick config: kubectl get configmap -n falco
```

---

## Falco vs Other Tools — CKS Mindset

```
Timeline of an attack — what each tool catches:

  Developer    →   Build   →   Deploy   →   Running   →   Exfil
  writes code      Trivy        OPA         Falco         Falco
                 (vuln scan)  (bad config)  (shell)     (outbound)
```

**Falco does NOT prevent attacks** — it detects them. Think of it as CCTV, not a lock. The locks are NetworkPolicy + PSA + Gatekeeper + AppArmor. Falco tells you when someone gets past the locks.

**Falco's limitations:**
- Cannot stop a syscall (it's observational, not blocking — unlike seccomp)
- Cannot see encrypted traffic content (only connection metadata)
- Generates noise if tuned poorly — threshold fatigue is a real ops problem

**In production, Falco fires → Sidekick routes to Slack → on-call responds within SLA.**

---

## Falco in Real Production (vs What We Did)

| What we did | What production looks like |
|------------|--------------------------|
| Helm install via `.sh` script | Helm chart managed by ArgoCD |
| Rules in `security/falco/rules/` | Rules in dedicated platform repo, PR-reviewed |
| Alerts in `kubectl logs` | Falco Sidekick → Loki → Grafana dashboards |
| Manual rule testing | Automated regression tests via `sysdig-inspect` or `falco --validate` |
| Single cluster | Same rules deployed to staging + prod via GitOps |
| No alert routing | PagerDuty integration: CRITICAL → immediate page, WARNING → ticket |

---

## Phase Progress

```
✅ Phase 4.1 — kube-bench CIS Hardening
✅ Phase 4.2 — etcd Encryption at Rest
✅ Phase 4.3 — Fine-grained RBAC
✅ Phase 4.4 — AppArmor Custom Profiles
✅ Phase 4.5 — Custom seccomp Profiles
✅ Phase 4.6 — OPA Gatekeeper
✅ Phase 4.7 — Falco Runtime Threat Detection (this phase)
⏳ Phase 4.8 — cert-manager + TLS Ingress
⏳ Phase 4.9 — mTLS (order → payment)
⏳ Phase 4.10 — gVisor RuntimeClass
⏳ Phase 4.11 — Vault + External Secrets Operator
```
