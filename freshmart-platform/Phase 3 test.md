# Phase 3 — FreshMart CKS Testing Checklist

> **Cluster:** `freshmart-cks` (Kind — 1 control-plane + 2 workers)
> **Context:** `kind-freshmart-cks`
> **Scope:** Tests ONLY for what is implemented in Phase 3 (✅ items).
> Phase 4+ items are explicitly marked as out of scope.

---

## CKS Domain Coverage — Phase 3

```
┌──────────────────────────────────┬────────┬────────────────────┐
│ Domain                           │ Weight │ Phase 3 Coverage   │
├──────────────────────────────────┼────────┼────────────────────┤
│ 1. Cluster Setup                 │  10%   │ ████████░░  60%    │
│ 2. Cluster Hardening             │  15%   │ ██████░░░░  40%    │
│ 3. System Hardening              │  15%   │ ████░░░░░░  35%    │
│ 4. Microservice Vulnerabilities  │  20%   │ ██████░░░░  50%    │
│ 5. Supply Chain Security         │  20%   │ ████░░░░░░  30%    │
│ 6. Monitoring & Runtime Security │  20%   │ █░░░░░░░░░  10%    │
└──────────────────────────────────┴────────┴────────────────────┘
```

---

## Quick Reference

| # | Test | CKS Domain | Covered In |
|---|------|------------|------------|
| 1 | All pods Running | Cluster Setup | Phase 3 |
| 2 | Ingress routes all services | Cluster Setup | Phase 3 |
| 3 | default-deny-all in every namespace | Cluster Setup | Phase 3 |
| 4 | product-service → payment: BLOCKED | Cluster Setup | Phase 3 |
| 5 | order-service → payment: ALLOWED | Cluster Setup | Phase 3 |
| 6 | Dedicated ServiceAccount per service | Cluster Hardening | Phase 3 |
| 7 | SA token NOT mounted in pods | Cluster Hardening | Phase 3 |
| 8 | PSA restricted on tesco-core | Cluster Hardening | Phase 3 |
| 9 | PSA restricted on tesco-payments | Cluster Hardening | Phase 3 |
| 10 | seccompProfile: RuntimeDefault on all pods | System Hardening | Phase 3 |
| 11 | runAsNonRoot + explicit UID | System Hardening | Phase 3 |
| 12 | allowPrivilegeEscalation: false | System Hardening | Phase 3 |
| 13 | capabilities: drop ALL | System Hardening | Phase 3 |
| 14 | payment-service readOnlyRootFilesystem | System Hardening | Phase 3 |
| 15 | Minimal base images (distroless) | System Hardening | Phase 3 |
| 16 | PSA restricted enforced | Microservice Vulns | Phase 3 |
| 17 | Security contexts at pod + container level | Microservice Vulns | Phase 3 |
| 18 | Resource requests + limits on all containers | Microservice Vulns | Phase 3 |
| 19 | NetworkPolicy isolation per namespace | Microservice Vulns | Phase 3 |
| 20 | payment-service zero public ingress | Microservice Vulns | Phase 3 |
| 21 | Multi-stage Dockerfiles (no build tools at runtime) | Supply Chain | Phase 3 |
| 22 | Non-root user in Dockerfile | Supply Chain | Phase 3 |
| 23 | imagePullPolicy: Never on freshmart images | Supply Chain | Phase 3 |
| 24 | seccomp reduces syscall noise | Runtime Security | Phase 3 |
| 25 | tesco-monitoring namespace ready for Falco | Runtime Security | Phase 3 |
| F1 | Products API returns data | Functional | Phase 3 |
| F2 | Cart API adds items | Functional | Phase 3 |
| F3 | Full checkout (order + payment) succeeds | Functional | Phase 3 |

---

## Domain 1 — Cluster Setup (10% weight · 60% covered in Phase 3)

**What Phase 3 covers:** NetworkPolicies (default-deny + explicit allow), Ingress routing
**What Phase 4 adds:** Ingress TLS, CIS Benchmark (kube-bench), node metadata protection

---

### Test 1 — All pods Running

```bash
kubectl get pods -A
```

**Expected:** All app pods show `Running`. `Completed` is fine for init jobs.

```
ingress-nginx   ingress-nginx-controller-*     1/1   Running
tesco-core      cart-service-* (×2)            1/1   Running
tesco-core      order-service-* (×2)           1/1   Running
tesco-core      product-service-* (×2)         1/1   Running
tesco-data      postgresql-0                   1/1   Running
tesco-frontend  frontend-*                     1/1   Running
tesco-payments  payment-service-*              1/1   Running
```

---

### Test 2 — Ingress routes all services correctly

```bash
# Frontend (Next.js)
curl -s -o /dev/null -w "Frontend:        %{http_code}\n" http://localhost

# Product service
curl -s -o /dev/null -w "Product API:     %{http_code}\n" http://localhost/api/products

# Cart service
curl -s -o /dev/null -w "Cart API:        %{http_code}\n" http://localhost/api/cart/test

# Order service
curl -s -o /dev/null -w "Order API:       %{http_code}\n" http://localhost/api/orders
```

**Expected:** `200` for frontend and products. `404` (not `502`/`503`) for cart/orders is acceptable — the service is reachable, just the session/resource doesn't exist yet.

---

### Test 3 — default-deny-all NetworkPolicy in every namespace

```bash
kubectl get networkpolicy -A | grep default-deny-all
```

**Expected — one entry per app namespace:**

```
tesco-core        default-deny-all
tesco-data        default-deny-all
tesco-frontend    default-deny-all
tesco-messaging   default-deny-all
tesco-monitoring  default-deny-all
tesco-payments    default-deny-all
```

**Why this matters:** If default-deny doesn't exist, any pod can reach any other pod by default. This is the most common misconfiguration in Kubernetes clusters.

---

### Test 4 — NetworkPolicy: product-service CANNOT reach payment-service

```bash
kubectl exec -n tesco-core deploy/product-service -- \
  wget -qO- --timeout=5 \
  http://payment-service.tesco-payments.svc.cluster.local:8004/health \
  2>&1 || echo "✅ BLOCKED — NetworkPolicy working"
```

**Expected:** `wget: download timed out` or `✅ BLOCKED`
**Fail:** `{"status":"healthy"}` — means NetworkPolicy is broken

**CKS exam scenario:** "Verify that pod A cannot communicate with pod B."
The iptables rules generated from the NetworkPolicy drop the packet at the kernel — the application never even sees the connection attempt.

---

### Test 5 — NetworkPolicy: order-service CAN reach payment-service

```bash
kubectl exec -n tesco-core deploy/order-service -- \
  wget -qO- --timeout=5 \
  http://payment-service.tesco-payments.svc.cluster.local:8004/health \
  2>&1
```

**Expected:** `{"status":"healthy","service":"payment-service"}`

**Why both Test 4 and 5 matter:** Test 4 proves deny works. Test 5 proves the explicit allow rule is correctly scoped to `pod=order-service` only. Both must pass.

---

## Domain 2 — Cluster Hardening (15% weight · 40% covered in Phase 3)

**What Phase 3 covers:** Dedicated ServiceAccounts, automountServiceAccountToken: false, PSA enforcement
**What Phase 4 adds:** Fine-grained RBAC Roles, restrict anonymous API access, etcd encryption, K8s audit policy

---

### Test 6 — Dedicated ServiceAccount per service

```bash
kubectl get serviceaccounts -A | grep -v "default\|kube\|ingress\|local-path"
```

**Expected:** One named ServiceAccount per service:

```
tesco-core      cart-service-sa
tesco-core      order-service-sa
tesco-core      product-service-sa
tesco-data      postgresql-sa
tesco-frontend  frontend-sa
tesco-messaging kafka-sa
tesco-payments  payment-service-sa
```

---

### Test 7 — SA token NOT mounted in pods

```bash
kubectl exec -n tesco-core deploy/product-service -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1
```

**Expected:** `ls: /var/run/secrets/kubernetes.io/serviceaccount/: No such file or directory`

```bash
# Also verify on payment-service
kubectl exec -n tesco-payments deploy/payment-service -- \
  ls /var/run/secrets/ 2>&1
```

**Expected:** Empty or does not exist.

**CKS exam scenario:** "A pod should not have access to the Kubernetes API — remediate this."
By default, every pod gets a mounted token. With `automountServiceAccountToken: false`, the token is never mounted — a compromised container cannot call `kubectl get secrets -A`.

---

### Test 8 — PSA enforced as `restricted` on tesco-core

```bash
# Check the label
kubectl get ns tesco-core \
  -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'
```

**Expected:** `restricted`

```bash
# Prove it blocks a non-compliant pod (running as root)
kubectl run psa-test-$RANDOM \
  --image=nginx \
  --namespace=tesco-core \
  --overrides='{"spec":{"containers":[{"name":"t","image":"nginx","securityContext":{"runAsUser":0}}]}}' \
  2>&1
```

**Expected:** `Error from server (Forbidden): ... violates PodSecurity "restricted:latest"`

---

### Test 9 — PSA enforced as `restricted` on tesco-payments

```bash
kubectl get ns tesco-payments \
  -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'
```

**Expected:** `restricted`

```bash
# Prove it blocks a privileged pod
kubectl run psa-pay-test-$RANDOM \
  --image=nginx \
  --namespace=tesco-payments \
  --overrides='{"spec":{"containers":[{"name":"t","image":"nginx","securityContext":{"privileged":true}}]}}' \
  2>&1
```

**Expected:** `Error from server (Forbidden): ... violates PodSecurity "restricted:latest"`

---

## Domain 3 — System Hardening (15% weight · 35% covered in Phase 3)

**What Phase 3 covers:** seccomp RuntimeDefault, runAsNonRoot, allowPrivilegeEscalation: false, capabilities: drop ALL, readOnlyRootFilesystem (payment), distroless images
**What Phase 4 adds:** Custom AppArmor profiles, custom seccomp profiles per service

---

### Test 10 — seccompProfile: RuntimeDefault on all pods

```bash
kubectl get pods -n tesco-core \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext.seccompProfile.type}{"\n"}{end}'
```

**Expected:** Every pod shows `RuntimeDefault`

```bash
kubectl get pods -n tesco-payments \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext.seccompProfile.type}{"\n"}{end}'
```

**CKS relevance:** RuntimeDefault restricts the container to the common set of syscalls. Reduces the kernel attack surface and is mandatory for PSA `restricted` level.

---

### Test 11 — runAsNonRoot + explicit UID

```bash
# Check declared UIDs in pod specs
for ns in tesco-core tesco-payments tesco-frontend; do
  echo "=== $ns ==="
  kubectl get pods -n $ns \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}UID={.spec.securityContext.runAsUser}{"\n"}{end}'
done
```

**Expected:** `UID=10001` (Python services), `UID=65532` (payment-service, frontend). No `UID=0`.

```bash
# Confirm live UID inside a running container
kubectl exec -n tesco-core deploy/product-service -- id
```

**Expected:** `uid=10001(appuser) gid=10001(appgroup)`

---

### Test 12 — allowPrivilegeEscalation: false on all containers

```bash
kubectl get pods -n tesco-core -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pod in data['items']:
    for c in pod['spec']['containers']:
        ape = c.get('securityContext', {}).get('allowPrivilegeEscalation', 'NOT SET')
        print(f\"{pod['metadata']['name']}/{c['name']}: allowPrivilegeEscalation={ape}\")
"
```

**Expected:** Every line shows `allowPrivilegeEscalation=False`

---

### Test 13 — capabilities: drop ALL on all containers

```bash
kubectl get pods -n tesco-core -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pod in data['items']:
    for c in pod['spec']['containers']:
        caps = c.get('securityContext', {}).get('capabilities', {}).get('drop', [])
        print(f\"{pod['metadata']['name']}/{c['name']}: drop={caps}\")
"
```

**Expected:** Every line shows `drop=['ALL']`

**CKS relevance:** Linux capabilities like `NET_RAW`, `SYS_ADMIN`, `NET_BIND_SERVICE` allow container escape or privilege escalation. Dropping ALL removes every capability the process doesn't need.

---

### Test 14 — payment-service: readOnlyRootFilesystem

```bash
# Check the spec
kubectl get pod -n tesco-payments \
  -o jsonpath='{.items[0].spec.containers[0].securityContext.readOnlyRootFilesystem}'
```

**Expected:** `true`

```bash
# Prove it's actually enforced at runtime
kubectl exec -n tesco-payments deploy/payment-service -- \
  touch /tmp/test 2>&1
```

**Expected:** `touch: /tmp/test: Read-only file system`

**CKS relevance:** A compromised payment-service container cannot write malware, modify binaries, or establish persistence. The attacker's RCE is ephemeral — nothing survives a container restart.

---

### Test 15 — payment-service uses distroless image (no shell)

```bash
# Check the image
kubectl get pod -n tesco-payments \
  -o jsonpath='{.items[0].spec.containers[0].image}'
```

**Expected:** `freshmart/payment-service:latest` (built on `gcr.io/distroless/static-debian12`)

```bash
# Prove there is NO shell inside the container
kubectl exec -n tesco-payments deploy/payment-service -- /bin/sh 2>&1
```

**Expected:** `error: ... executable file not found` or `no such file or directory`

**CKS relevance:** Distroless = zero OS tooling. No `curl`, no `wget`, no `bash`. Even if RCE is achieved, the attacker cannot run post-exploitation tools interactively.

---

## Domain 4 — Minimize Microservice Vulnerabilities (20% weight · 50% covered in Phase 3)

**What Phase 3 covers:** PSA restricted enforcement, full security contexts (pod + container), resource limits, NetworkPolicy isolation, payment-service zero public access
**What Phase 4 adds:** OPA Gatekeeper, Vault + External Secrets, mTLS order→payment, gVisor RuntimeClass

---

### Test 16 — PSA restricted enforced (same as Test 8 — intentional overlap)

PSA is both a Cluster Hardening and a Microservice Vulnerability control. Reference Tests 8 and 9.

---

### Test 17 — Security contexts at both pod AND container level

```bash
kubectl get pod -n tesco-core -l app=product-service \
  -o jsonpath='{.items[0].spec.securityContext}' | python3 -m json.tool
```

**Expected pod-level context:**
```json
{
  "fsGroup": 10001,
  "runAsGroup": 10001,
  "runAsNonRoot": true,
  "runAsUser": 10001,
  "seccompProfile": { "type": "RuntimeDefault" }
}
```

```bash
kubectl get pod -n tesco-core -l app=product-service \
  -o jsonpath='{.items[0].spec.containers[0].securityContext}' | python3 -m json.tool
```

**Expected container-level context:**
```json
{
  "allowPrivilegeEscalation": false,
  "capabilities": { "drop": ["ALL"] },
  "readOnlyRootFilesystem": false
}
```

---

### Test 18 — Resource requests + limits on all containers

```bash
kubectl get pods -n tesco-core -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pod in data['items']:
    for c in pod['spec']['containers']:
        res = c.get('resources', {})
        print(f\"{pod['metadata']['name']}/{c['name']}\")
        print(f\"  requests: {res.get('requests', 'MISSING')}\")
        print(f\"  limits:   {res.get('limits', 'MISSING')}\")
"
```

**Expected:** Every container has both `requests` and `limits` set for CPU and memory. `MISSING` is a fail.

**CKS relevance:** Without limits, a single compromised or buggy container can exhaust all node CPU/memory, causing a cluster-wide DoS.

---

### Test 19 — payment-service has ZERO public ingress route

```bash
# No route to payment-service through nginx ingress
curl -sv http://localhost/api/payments 2>&1 | grep "< HTTP"
```

**Expected:** `404` from nginx (no route defined) — **never** a `200` or `{"status":"healthy"}` from payment-service directly.

```bash
# Confirm Ingress objects have no payment-service backend
kubectl get ingress -A -o yaml | grep -i "payment" || echo "✅ No payment route in Ingress"
```

**Expected:** `✅ No payment route in Ingress`

---

## Domain 5 — Supply Chain Security (20% weight · 30% covered in Phase 3)

**What Phase 3 covers:** Minimal base images, multi-stage builds, non-root in Dockerfile, imagePullPolicy: Never
**What Phase 4/5 adds:** Trivy scanning in CI, Cosign image signing, OPA allowed registries policy, SBOM generation

---

### Test 20 — Multi-stage Dockerfiles (no build tools in runtime image)

```bash
# Verify python build tools are NOT in the product-service runtime image
kubectl exec -n tesco-core deploy/product-service -- \
  pip --version 2>&1
```

**Expected:** `pip: command not found` — pip is only in the builder stage, not the runner.

```bash
# Verify Go compiler is NOT in payment-service runtime image
kubectl exec -n tesco-payments deploy/payment-service -- \
  ls /usr/local/go 2>&1
```

**Expected:** `No such file or directory` — only the compiled binary is in the distroless image.

---

### Test 21 — Non-root user baked into Dockerfile

```bash
# product-service: appuser created in Dockerfile
kubectl exec -n tesco-core deploy/product-service -- whoami 2>&1
```

**Expected:** `appuser` (uid 10001 — created with `useradd` in Dockerfile)

```bash
# payment-service: nonroot from distroless
kubectl exec -n tesco-payments deploy/payment-service -- \
  cat /etc/passwd 2>&1
```

**Expected:** Permission denied or file not found — distroless has no `/etc/passwd`. The image runs as uid 65532 (`nonroot`) by definition.

---

### Test 22 — imagePullPolicy: Never on all freshmart images

```bash
kubectl get pods -n tesco-core \
  -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\t"}{.imagePullPolicy}{"\n"}{end}' | sort -u
```

**Expected:** All `freshmart/*` images show `Never`

```bash
kubectl get pods -n tesco-payments \
  -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\t"}{.imagePullPolicy}{"\n"}{end}'
```

**Expected:** `freshmart/payment-service:latest    Never`

**CKS relevance:** `imagePullPolicy: Never` guarantees only pre-vetted images loaded via `kind load docker-image` can run. No surprise pulls from public registries during deployment.

---

## Domain 6 — Monitoring & Runtime Security (20% weight · 10% covered in Phase 3)

**What Phase 3 covers:** seccomp RuntimeDefault (prerequisite foundation), tesco-monitoring namespace
**What Phase 4 adds:** Falco + custom rules, K8s audit policy, immutable containers, behavioural anomaly detection

---

### Test 23 — seccomp RuntimeDefault reduces syscall noise

```bash
# Verify seccomp is active on all pods (same as Test 10 — reinforced here as runtime control)
kubectl get pods -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.securityContext.seccompProfile.type}{"\n"}{end}' \
  | grep -v "kube-system\|ingress-nginx\|local-path"
```

**Expected:** Every app pod shows `RuntimeDefault`

**Why this is a runtime security control:** RuntimeDefault instructs the kernel's seccomp filter to audit unexpected syscalls. Falco (Phase 4) reads those audit events to generate alerts.

---

### Test 24 — tesco-monitoring namespace ready for Falco

```bash
kubectl get ns tesco-monitoring \
  -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'
```

**Expected:** `privileged`

**Why privileged PSA here?** Falco needs to load a kernel module (eBPF probe) to observe syscalls cluster-wide. This requires privileged access — hence the dedicated namespace with `privileged` PSA, isolated from all other workloads.

---

## Functional Tests — End-to-End Checkout Flow

### Test F1 — Products API

```bash
curl -s http://localhost/api/products | python3 -m json.tool | head -20
```

**Expected:** JSON array with 12 products, each with `name`, `price`, `category`, `stock_quantity`.

---

### Test F2 — Add to cart

```bash
curl -s -X POST http://localhost/api/cart/phase3-test/items \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "quantity": 2}' | python3 -m json.tool
```

**Expected:** Cart item response with `product_id: 1`, `quantity: 2`, and a `price`.

```bash
# View the cart
curl -s http://localhost/api/cart/phase3-test | python3 -m json.tool
```

**Expected:** Cart with `items` array and `total`.

---

### Test F3 — Full checkout (order-service → payment-service → PostgreSQL)

```bash
curl -s -X POST http://localhost/api/orders \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "phase3-test",
    "delivery_address": {
      "full_name": "CKS Tester",
      "address_line1": "1 Kubernetes Lane",
      "city": "London",
      "postcode": "EC1A 1BB"
    },
    "payment_details": {
      "card_number": "4242424242424242",
      "expiry": "12/27",
      "cvv": "123"
    }
  }' | python3 -m json.tool
```

**Expected:**
```json
{
  "id": "ORD-xxxxxxxx",
  "status": "confirmed",
  "payment_status": "success",
  "total": ...
}
```

This single test validates the entire microservice chain:
`nginx ingress → order-service → cart-service → payment-service → PostgreSQL`

---

## Automated Test Script

Save as `run-phase3-tests.sh` inside `freshmart-platform/`, then `chmod +x run-phase3-tests.sh && ./run-phase3-tests.sh`

```bash
#!/bin/bash
# FreshMart Phase 3 — CKS Automated Test Runner
# Tests ONLY what is implemented in Phase 3

set -uo pipefail
PASS=0; FAIL=0

check() {
  local desc="$1"; local cmd="$2"; local expect="$3"
  local result
  result=$(eval "$cmd" 2>&1)
  if echo "$result" | grep -q "$expect"; then
    echo "✅ PASS  $desc"
    ((PASS++))
  else
    echo "❌ FAIL  $desc"
    echo "         Expected: '$expect'"
    echo "         Got:      '$(echo "$result" | head -c 150)'"
    ((FAIL++))
  fi
}

echo ""
echo "════════════════════════════════════════════════"
echo "  FreshMart Phase 3 — CKS Verification Tests"
echo "════════════════════════════════════════════════"
echo ""

echo "── Domain 1: Cluster Setup ─────────────────────"
check "postgresql-0 is Running" \
  "kubectl get pod postgresql-0 -n tesco-data --no-headers" "Running"
check "Ingress: products API reachable" \
  "curl -sf http://localhost/api/products" "price"
check "default-deny-all in tesco-core" \
  "kubectl get networkpolicy default-deny-all -n tesco-core --no-headers" "default-deny-all"
check "default-deny-all in tesco-payments" \
  "kubectl get networkpolicy default-deny-all -n tesco-payments --no-headers" "default-deny-all"
check "product-service CANNOT reach payment-service" \
  "kubectl exec -n tesco-core deploy/product-service -- wget -qO- --timeout=5 http://payment-service.tesco-payments.svc.cluster.local:8004/health 2>&1" \
  "timed out"
check "order-service CAN reach payment-service" \
  "kubectl exec -n tesco-core deploy/order-service -- wget -qO- --timeout=10 http://payment-service.tesco-payments.svc.cluster.local:8004/health 2>&1" \
  "healthy"

echo ""
echo "── Domain 2: Cluster Hardening ─────────────────"
check "product-service-sa exists" \
  "kubectl get sa product-service-sa -n tesco-core --no-headers" "product-service-sa"
check "payment-service-sa exists" \
  "kubectl get sa payment-service-sa -n tesco-payments --no-headers" "payment-service-sa"
check "SA token NOT mounted in product-service" \
  "kubectl exec -n tesco-core deploy/product-service -- ls /var/run/secrets/kubernetes.io/ 2>&1" \
  "No such file"
check "tesco-core PSA = restricted" \
  "kubectl get ns tesco-core -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'" \
  "restricted"
check "tesco-payments PSA = restricted" \
  "kubectl get ns tesco-payments -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'" \
  "restricted"
check "PSA blocks root pod in tesco-core" \
  "kubectl run psa-test-$RANDOM --image=nginx --namespace=tesco-core --overrides='{\"spec\":{\"containers\":[{\"name\":\"t\",\"image\":\"nginx\",\"securityContext\":{\"runAsUser\":0}}]}}' 2>&1" \
  "forbidden"

echo ""
echo "── Domain 3: System Hardening ──────────────────"
check "seccomp RuntimeDefault on product-service" \
  "kubectl get pods -n tesco-core -l app=product-service -o jsonpath='{.items[0].spec.securityContext.seccompProfile.type}'" \
  "RuntimeDefault"
check "seccomp RuntimeDefault on payment-service" \
  "kubectl get pods -n tesco-payments -o jsonpath='{.items[0].spec.securityContext.seccompProfile.type}'" \
  "RuntimeDefault"
check "runAsNonRoot on product-service" \
  "kubectl get pods -n tesco-core -l app=product-service -o jsonpath='{.items[0].spec.securityContext.runAsNonRoot}'" \
  "true"
check "product-service runs as uid 10001" \
  "kubectl exec -n tesco-core deploy/product-service -- id" \
  "10001"
check "allowPrivilegeEscalation=false on product-service" \
  "kubectl get pods -n tesco-core -l app=product-service -o jsonpath='{.items[0].spec.containers[0].securityContext.allowPrivilegeEscalation}'" \
  "false"
check "payment-service readOnlyRootFilesystem=true" \
  "kubectl get pod -n tesco-payments -o jsonpath='{.items[0].spec.containers[0].securityContext.readOnlyRootFilesystem}'" \
  "true"
check "payment-service filesystem is actually read-only" \
  "kubectl exec -n tesco-payments deploy/payment-service -- touch /tmp/test 2>&1" \
  "Read-only"
check "payment-service has no shell (distroless)" \
  "kubectl exec -n tesco-payments deploy/payment-service -- /bin/sh 2>&1" \
  "no such file"

echo ""
echo "── Domain 4: Microservice Vulnerabilities ──────"
check "payment-service: zero public ingress route" \
  "kubectl get ingress -A -o yaml 2>&1" \
  "No payment route" # expects grep to fail = no payment route
  # override: use a positive check instead
check "No Ingress backend for payment" \
  "kubectl get ingress -A -o yaml | grep payment || echo 'NO_PAYMENT_ROUTE'" \
  "NO_PAYMENT_ROUTE"

echo ""
echo "── Domain 5: Supply Chain Security ─────────────"
check "imagePullPolicy=Never on product-service" \
  "kubectl get pods -n tesco-core -l app=product-service -o jsonpath='{.items[0].spec.containers[0].imagePullPolicy}'" \
  "Never"
check "imagePullPolicy=Never on payment-service" \
  "kubectl get pods -n tesco-payments -o jsonpath='{.items[0].spec.containers[0].imagePullPolicy}'" \
  "Never"
check "No pip in product-service runtime" \
  "kubectl exec -n tesco-core deploy/product-service -- pip --version 2>&1" \
  "not found"

echo ""
echo "── Domain 6: Runtime Security ──────────────────"
check "tesco-monitoring namespace exists" \
  "kubectl get ns tesco-monitoring --no-headers" "tesco-monitoring"
check "tesco-monitoring PSA = privileged (ready for Falco)" \
  "kubectl get ns tesco-monitoring -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'" \
  "privileged"

echo ""
echo "── Functional Tests ────────────────────────────"
check "Products API returns product data" \
  "curl -sf http://localhost/api/products" "price"
check "Cart API accepts items" \
  "curl -sf -X POST http://localhost/api/cart/autotest-$RANDOM/items -H 'Content-Type: application/json' -d '{\"product_id\":1,\"quantity\":1}'" \
  "product_id"
check "Full checkout succeeds (order + payment)" \
  "curl -sf -X POST http://localhost/api/orders -H 'Content-Type: application/json' -d '{\"session_id\":\"autotest\",\"delivery_address\":{\"full_name\":\"Test\",\"address_line1\":\"1 St\",\"city\":\"London\",\"postcode\":\"EC1\"},\"payment_details\":{\"card_number\":\"4242424242424242\",\"expiry\":\"12/27\",\"cvv\":\"123\"}}'" \
  "confirmed"

echo ""
echo "════════════════════════════════════════════════"
echo "  Results: ${PASS} passed  |  ${FAIL} failed"
echo "════════════════════════════════════════════════"
echo ""
```

---

## What Phase 4 Will Add

The following are intentionally **not tested here** — they are Phase 4 scope:

| Control | Phase |
|---------|-------|
| Ingress TLS (cert-manager) | Phase 4 |
| CIS Benchmark scan (kube-bench) | Phase 4 |
| etcd encryption at rest | Phase 4 |
| K8s API audit policy | Phase 4 |
| Fine-grained RBAC Roles | Phase 4 |
| AppArmor custom profiles | Phase 4 |
| Custom seccomp profiles | Phase 4 |
| OPA Gatekeeper ConstraintTemplates | Phase 4 |
| Vault + External Secrets | Phase 4 |
| mTLS (order → payment) | Phase 4 |
| gVisor RuntimeClass for payment | Phase 4 |
| Falco install + custom rules | Phase 4 |
| Immutable containers (all services) | Phase 4 |
| Trivy image scanning | Phase 5 |
| Cosign image signing | Phase 5 |
| SBOM generation | Phase 5 |
