# Phase 4.3 — Fine-grained RBAC

> **Project:** FreshMart CKS DevSecOps Portfolio
> **Phase:** 4.3 of 8 — Fine-grained RBAC (Role-Based Access Control)
> **CKS Domain:** Cluster Hardening (15%)
> **kube-bench:** 5.1.1 → 5.1.13 (all RBAC WARNs)

---

## What Is Fine-grained RBAC?

RBAC (Role-Based Access Control) controls which Kubernetes API operations each identity (user, group, ServiceAccount) can perform. "Fine-grained" means applying **least privilege** — every identity gets exactly the permissions it needs, nothing more.

In the CKS context, RBAC hardening means:
1. No wildcard `*` permissions in any Role or ClusterRole you create
2. No unnecessary `cluster-admin` bindings
3. `default` ServiceAccounts disabled across all namespaces
4. Service accounts have no K8s API access unless explicitly needed
5. No SA tokens mounted in pods that don't use them

---

## RBAC Building Blocks (CKS Reference)

```
Identity types:
  User           → human (e.g. admin, dev)
  Group          → set of users (e.g. system:masters)
  ServiceAccount → pod identity (e.g. product-service-sa)

Permission scopes:
  Role            → permissions within ONE namespace
  ClusterRole     → permissions cluster-wide OR reusable across namespaces

Binding types:
  RoleBinding        → grants a Role/ClusterRole to an identity in ONE namespace
  ClusterRoleBinding → grants a ClusterRole to an identity cluster-wide

Evaluation:
  Default = DENY ALL
  Access granted only by an explicit Role/ClusterRole binding
  Bindings are additive — there is no "deny" rule in RBAC
```

---

## FreshMart RBAC Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Phase 3 (existing 01-rbac.yaml)                                │
│                                                                  │
│  product-service-sa ──► NO Role bound ──► no K8s API access    │
│  cart-service-sa    ──► NO Role bound ──► no K8s API access    │
│  order-service-sa   ──► NO Role bound ──► no K8s API access    │
│  payment-service-sa ──► NO Role bound ──► no K8s API access    │
│  frontend-sa        ──► NO Role bound ──► no K8s API access    │
│                                                                  │
│  (Services only talk to PostgreSQL over HTTP — no K8s API use) │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Phase 4.3 addition (10-rbac-hardening/)                        │
│                                                                  │
│  tesco-core/default SA      → automountServiceAccountToken=false│
│  tesco-payments/default SA  → automountServiceAccountToken=false│
│  tesco-frontend/default SA  → automountServiceAccountToken=false│
│  tesco-data/default SA      → automountServiceAccountToken=false│
│  tesco-messaging/default SA → automountServiceAccountToken=false│
│  tesco-monitoring/default SA→ automountServiceAccountToken=false│
└─────────────────────────────────────────────────────────────────┘
```

**Why our services have NO Roles:** FreshMart's microservices are database-backed HTTP APIs. They call PostgreSQL and each other over HTTP — they never call the Kubernetes API. Giving them K8s API access would violate least privilege.

---

## What We Fixed in Phase 4.3

### The Default ServiceAccount Problem

Every namespace gets a `default` ServiceAccount automatically. By default:
- `automountServiceAccountToken: true`
- Any pod that doesn't specify `serviceAccountName` uses `default`
- That pod gets a K8s API token mounted at `/var/run/secrets/kubernetes.io/serviceaccount/`

**Attack scenario:** A developer deploys a debug pod without specifying a SA. It gets the `default` SA token. An attacker who compromises that pod can call `kubectl get secrets -n tesco-core` — even though the pod was never supposed to have API access.

**Fix:** Set `automountServiceAccountToken: false` on the `default` SA in every namespace.

### Files Created

```
freshmart-platform/
├── k8s/10-rbac-hardening/
│   └── default-sa-patch.yaml     ← patches default SA in all 6 app namespaces
└── infra/kind/
    └── rbac-audit.sh             ← automated RBAC audit (kube-bench 5.1.x)
```

---

## How to Apply

```bash
cd ~/Downloads/DevSecOps\ Projects/CKS-\ Real\ case/freshmart-platform

# Apply the default SA patches
kubectl apply -f k8s/10-rbac-hardening/default-sa-patch.yaml

# Run the RBAC audit
chmod +x infra/kind/rbac-audit.sh
./infra/kind/rbac-audit.sh
```

---

## Actual Audit Output & Analysis

Running `./infra/kind/rbac-audit.sh` produced:

```
Results: 25 passed  |  8 failed  |  10 warnings
```

### The 8 "FAILs" Were All False Positives

This is a critical real-world lesson: **audit tools report on what they see, not on whether it's intentional**. Every single FAIL was expected system behaviour, not a real security problem.

| FAIL reported | Why it's a false positive | Action |
|---|---|---|
| `cluster/cluster-admin` has wildcard `*` | This is the built-in K8s `cluster-admin` ClusterRole — it is **supposed** to have `*`. You cannot and should not remove it | Exclude built-in roles from wildcard check |
| `cluster-admin` binds `system:masters` | This is the built-in kubeadm ClusterRoleBinding that makes the cluster work. Removing it breaks `kubectl` | Exclude built-in binding from check |
| SA token exec `x509` TLS errors | Kind worker nodes use IP addresses not included in the kubelet TLS certificate SANs. `kubectl exec` fails with a cert error — **not** because a token is mounted | Use pod spec inspection instead of exec |

### The 10 WARNs Were All Expected

| WARN | Why it's expected |
|---|---|
| `ingress-nginx` roles have secrets access | ingress-nginx legitimately reads TLS certificate Secrets for Ingress termination |
| `cluster/admin`, `cluster/edit` have secrets access | Built-in K8s ClusterRoles — `admin` and `edit` are designed to include secrets access |
| `local-path-provisioner` can create pods | Kind's storage provisioner creates helper pods to provision PVCs |
| `cluster/admin`, `cluster/edit` can create pods | Built-in roles — expected |

### The 25 PASSes Are What Matter

All checks that apply to **FreshMart's own resources** passed cleanly:

```
✅ No non-system cluster-admin bindings
✅ tesco-core: no pods using default ServiceAccount        (×6 namespaces)
✅ tesco-core/default SA: automountServiceAccountToken=false  (×6 namespaces)
✅ tesco-core/cart-service-sa: automountServiceAccountToken=false
✅ tesco-core/order-service-sa: automountServiceAccountToken=false
✅ tesco-core/product-service-sa: automountServiceAccountToken=false
✅ tesco-payments/payment-service-sa: automountServiceAccountToken=false
✅ tesco-frontend/frontend-sa: automountServiceAccountToken=false
✅ tesco-data/postgresql-sa: automountServiceAccountToken=false
✅ tesco-messaging/kafka-sa: automountServiceAccountToken=false
✅ No non-system bindings to system:masters
✅ product-service-sa: no Role/ClusterRole bound
✅ cart-service-sa: no Role/ClusterRole bound
✅ order-service-sa: no Role/ClusterRole bound
✅ payment-service-sa: no Role/ClusterRole bound
✅ frontend-sa: no Role/ClusterRole bound
```

### Audit Script Fix — v2

The script was updated to suppress the three categories of false positives:

**Fix 1 — Wildcard check now excludes built-in ClusterRoles:**
```python
BUILTIN_ROLES = {'cluster-admin', 'admin', 'edit', 'view'}
if name in BUILTIN_ROLES: continue   # skip — wildcards are expected here
```

**Fix 2 — system:masters check now excludes the built-in binding:**
```python
BUILTIN_BINDINGS = {'cluster-admin'}
if name in BUILTIN_BINDINGS: continue   # kubeadm creates this — required
```

**Fix 3 — SA token check uses pod spec inspection instead of `kubectl exec`:**

`kubectl exec` fails in Kind because worker node IPs aren't in the kubelet's TLS cert SANs. The fix inspects the pod spec directly — which is actually more accurate:
```bash
# Check via pod spec — no exec needed
kubectl get pod "$POD_NAME" -n "$NS" -o json | python3 -c "
  vols = pod.get('spec', {}).get('volumes') or []
  has_token = any('kube-api-access' in v.get('name','') for v in vols)
"
```

After the fix, the audit runs cleanly with **0 false-positive FAILs**.

---

## Verification — Practical Tests

### Test 1 — Default SAs have automountServiceAccountToken=false

```bash
for ns in tesco-core tesco-payments tesco-frontend tesco-data tesco-messaging tesco-monitoring; do
  echo -n "$ns/default → "
  kubectl get serviceaccount default -n $ns \
    -o jsonpath='{.automountServiceAccountToken}'
  echo ""
done
```

**Expected:** `false` for every namespace.

---

### Test 2 — Custom SAs have no Role bindings

```bash
kubectl get rolebindings,clusterrolebindings -A -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
freshmart_sas = ['product-service-sa','cart-service-sa','order-service-sa',
                 'payment-service-sa','frontend-sa','postgresql-sa','kafka-sa']
found = False
for item in data.get('items', []):
    for subj in item.get('subjects', []):
        if subj.get('kind') == 'ServiceAccount' and subj.get('name') in freshmart_sas:
            print(f\"WARN: {item['metadata']['name']} binds {subj['name']}\")
            found = True
if not found:
    print('PASS: No Role bindings on any FreshMart service account')
"
```

**Expected:** `PASS: No Role bindings on any FreshMart service account`

---

### Test 3 — SA token NOT mounted in running pods (pod spec method)

```bash
for ns_app in \
  "tesco-core:product-service" \
  "tesco-core:cart-service" \
  "tesco-core:order-service" \
  "tesco-payments:payment-service" \
  "tesco-frontend:frontend"; do
  NS="${ns_app%%:*}"; APP="${ns_app##*:}"
  POD=$(kubectl get pods -n $NS -l app=$APP --no-headers -o custom-columns="N:.metadata.name" | head -1)
  echo -n "$NS/$APP ($POD) → token volume: "
  kubectl get pod $POD -n $NS -o json | python3 -c "
import json,sys
pod=json.load(sys.stdin)
vols=pod.get('spec',{}).get('volumes') or []
has=any('kube-api-access' in v.get('name','') for v in vols)
print('PRESENT (check config)' if has else 'NOT PRESENT ✓')
"
done
```

**Expected:** `NOT PRESENT ✓` for every pod.

---

### Test 4 — Prove default SA token is blocked (simulate the attack)

```bash
# Create a test pod WITHOUT specifying serviceAccountName — uses 'default' SA
kubectl run rbac-test \
  --image=busybox:1.35 \
  --namespace=tesco-core \
  --restart=Never \
  --command -- sleep 3600

kubectl wait pod rbac-test -n tesco-core --for=condition=Ready --timeout=30s

# Check if the token volume is present in the pod spec
kubectl get pod rbac-test -n tesco-core -o json | python3 -c "
import json,sys
pod=json.load(sys.stdin)
vols=pod.get('spec',{}).get('volumes') or []
has=any('kube-api-access' in v.get('name','') for v in vols)
print('Token volume present:', has)
sa=pod.get('spec',{}).get('serviceAccountName')
print('ServiceAccount used:', sa)
"
```

**Expected (after Phase 4.3):**
```
Token volume present: False
ServiceAccount used: default
```

The pod uses `default` SA, but since we patched `default` with `automountServiceAccountToken: false`, no token volume is injected.

```bash
# Clean up
kubectl delete pod rbac-test -n tesco-core
```

---

### Test 5 — Check what a FreshMart SA can actually do

```bash
# product-service-sa should have ZERO permissions
kubectl auth can-i --list \
  --as=system:serviceaccount:tesco-core:product-service-sa \
  -n tesco-core | grep -v "^Non-resource\|^\*\|^self"
```

**Expected:** Only `selfsubjectaccessreviews` — nothing else.

```bash
# Spot-check critical permissions
for verb_resource in "get secrets" "list pods" "create pods" "delete deployments"; do
  VERB="${verb_resource% *}"; RES="${verb_resource#* }"
  RESULT=$(kubectl auth can-i $VERB $RES -n tesco-core \
    --as=system:serviceaccount:tesco-core:product-service-sa 2>/dev/null)
  echo "product-service-sa can $verb_resource: $RESULT"
done
```

**Expected:** `no` for every check.

---

### Test 6 — No wildcard roles in FreshMart namespaces

```bash
kubectl get roles,clusterroles -A -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
BUILTIN = {'cluster-admin','admin','edit','view'}
wildcards = []
for item in data.get('items', []):
    name = item.get('metadata', {}).get('name', '')
    ns = item.get('metadata', {}).get('namespace', 'cluster')
    if name.startswith('system:') or name.startswith('kubeadm'): continue
    if name in BUILTIN: continue
    for rule in item.get('rules', []):
        if '*' in rule.get('verbs',[]) + rule.get('resources',[]) + rule.get('apiGroups',[]):
            wildcards.append(f'{ns}/{name}')
print('PASS: No custom wildcard roles' if not wildcards else 'FAIL: ' + str(wildcards))
"
```

**Expected:** `PASS: No custom wildcard roles`

---

### Test 7 — Full automated audit (v2 — no false positives)

```bash
./infra/kind/rbac-audit.sh
```

**Expected after script fix:**
```
════════════════════════════════════════════════════
  FreshMart Phase 4.3 — RBAC Audit
  kube-bench: 5.1.1 → 5.1.13
════════════════════════════════════════════════════
✅ PASS  No non-system cluster-admin bindings
✅ PASS  No non-system roles with broad secrets access
✅ PASS  No non-system roles with wildcard permissions
✅ PASS  tesco-core: no pods using default ServiceAccount
✅ PASS  tesco-core/default SA: automountServiceAccountToken=false
✅ PASS  tesco-payments/default SA: automountServiceAccountToken=false
  ... (×6 namespaces)
✅ PASS  tesco-core/cart-service-sa: automountServiceAccountToken=false
  ... (all custom SAs)
✅ PASS  No non-system bindings to system:masters group
✅ PASS  tesco-core/product-service (pod): no SA token volume in pod spec
  ... (all 5 services)
✅ PASS  tesco-core/product-service-sa: no Role/ClusterRole bound
  ... (all 5 custom SAs)

Results: 33 passed  |  0 failed  |  10 warnings

Note: WARNs on built-in roles (cluster-admin, admin, edit,
ingress-nginx, local-path-provisioner) are expected — these are
system/infrastructure components, not FreshMart app roles.
```

---

## Important RBAC Commands

### Inspect permissions

```bash
# What can a specific SA do?
kubectl auth can-i --list \
  --as=system:serviceaccount:<ns>:<sa-name> -n <ns>

# Can a specific SA do a specific action?
kubectl auth can-i <verb> <resource> -n <ns> \
  --as=system:serviceaccount:<ns>:<sa-name>

# View all role bindings in a namespace
kubectl get rolebindings -n tesco-core -o wide

# View all cluster-wide bindings (filter system noise)
kubectl get clusterrolebindings -o wide \
  | grep -v "^system:\|^kubeadm\|^kindnet\|^local-path\|^ingress\|^kube-proxy\|^coredns"

# What Roles exist in a namespace?
kubectl get roles -n tesco-core -o yaml
```

### Quick permission checks for FreshMart SAs

```bash
# All should return 'no'
kubectl auth can-i get secrets -n tesco-core \
  --as=system:serviceaccount:tesco-core:product-service-sa

kubectl auth can-i get secrets -n tesco-payments \
  --as=system:serviceaccount:tesco-core:order-service-sa

kubectl auth can-i '*' '*' \
  --as=system:serviceaccount:tesco-payments:payment-service-sa
```

### Patch default SA (quick one-liner for any namespace)

```bash
kubectl patch serviceaccount default -n <namespace> \
  -p '{"automountServiceAccountToken": false}'
```

### Create minimal RBAC (pattern for future services)

```bash
# 1. Dedicated SA
kubectl create serviceaccount my-service-sa -n my-namespace

# 2. Minimal Role
kubectl create role pod-reader \
  --verb=get,list,watch \
  --resource=pods \
  -n my-namespace

# 3. Bind
kubectl create rolebinding my-service-pod-reader \
  --role=pod-reader \
  --serviceaccount=my-namespace:my-service-sa \
  -n my-namespace

# 4. Verify
kubectl auth can-i get pods -n my-namespace \
  --as=system:serviceaccount:my-namespace:my-service-sa  # yes
kubectl auth can-i delete pods -n my-namespace \
  --as=system:serviceaccount:my-namespace:my-service-sa  # no
```

---

## CKS Exam Scenarios

### Scenario 1 — "Create a SA with minimal permissions"

```
Task: Create SA 'log-reader' in 'monitoring'. Can only get/list pods and logs.

kubectl create sa log-reader -n monitoring
kubectl create role log-reader-role \
  --verb=get,list --resource=pods,pods/log -n monitoring
kubectl create rolebinding log-reader-rb \
  --role=log-reader-role \
  --serviceaccount=monitoring:log-reader -n monitoring

Verify:
kubectl auth can-i get pods -n monitoring \
  --as=system:serviceaccount:monitoring:log-reader    # yes
kubectl auth can-i get secrets -n monitoring \
  --as=system:serviceaccount:monitoring:log-reader    # no
```

### Scenario 2 — "Disable default SA token mounting"

```
Task: Ensure the default SA in 'production' does not auto-mount a token.

kubectl patch serviceaccount default -n production \
  -p '{"automountServiceAccountToken": false}'

Verify:
kubectl get sa default -n production \
  -o jsonpath='{.automountServiceAccountToken}'   # false
```

### Scenario 3 — "Find and remove excessive permissions"

```
Task: A ClusterRoleBinding gives an app SA cluster-admin. Fix it.

# Find it
kubectl get clusterrolebindings -o wide | grep cluster-admin

# Delete it
kubectl delete clusterrolebinding <name>

# Replace with minimal Role
kubectl create role minimal-role \
  --verb=get --resource=pods -n <namespace>
kubectl create rolebinding minimal-rb \
  --role=minimal-role \
  --serviceaccount=<namespace>:<sa-name> -n <namespace>
```

### Scenario 4 — "Audit RBAC for wildcards"

```bash
# Find any non-system role with wildcard permissions
kubectl get clusterroles -o json | python3 -c "
import json,sys
data=json.load(sys.stdin)
BUILTIN={'cluster-admin','admin','edit','view'}
for item in data['items']:
    name=item['metadata']['name']
    if name.startswith('system:') or name in BUILTIN: continue
    for rule in item.get('rules',[]):
        if '*' in rule.get('verbs',[])+rule.get('resources',[])+rule.get('apiGroups',[]):
            print(f'WILDCARD: {name}')
"
```

---

## RBAC Anti-patterns (CKS Exam Traps)

| Anti-pattern | Risk | Fix |
|---|---|---|
| `verbs: ["*"]` in custom role | Full API access | List only needed verbs |
| `resources: ["*"]` in custom role | Access to all resources | Specify exact resources |
| `apiGroups: ["*"]` in custom role | Access to all API groups | Specify exact groups |
| `ClusterRoleBinding` for namespace-scoped work | Cluster-wide access | Use `RoleBinding` instead |
| Binding to `cluster-admin` for app SA | Full cluster control | Create minimal Role |
| `serviceAccountName: default` in pod | Inherits default SA | Use dedicated SA |
| Not setting `automountServiceAccountToken: false` | Token mounted unnecessarily | Set on both SA and pod spec |
| Not filtering built-in roles in audit scripts | False positive FAILs | Exclude `system:*`, `kubeadm*`, `cluster-admin`, `admin`, `edit`, `view` |

---

## What We Achieved

| Before Phase 4.3 | After Phase 4.3 |
|---|---|
| `default` SAs: `automountServiceAccountToken=true` | `default` SAs: `automountServiceAccountToken=false` in all 6 namespaces |
| No audit tooling for RBAC | `rbac-audit.sh` covering kube-bench 5.1.1–5.1.13 |
| No wildcard check | Confirmed: zero custom wildcard roles |
| No cluster-admin audit | Confirmed: only built-in system bindings use cluster-admin |
| kube-bench 5.1.5 / 5.1.6: WARN | Satisfied: no pods use default SA, all SAs have token mounting disabled |
| False-positive audit noise | Script v2 correctly distinguishes built-in vs custom roles |

---

## Phase 4.3 Complete — What's Next

```
✅ Phase 4.1 — kube-bench CIS Hardening
✅ Phase 4.2 — etcd Encryption at Rest
✅ Phase 4.3 — Fine-grained RBAC
⏳ Phase 4.4 — AppArmor custom profiles
⏳ Phase 4.5 — Custom seccomp profiles
⏳ Phase 4.6 — OPA Gatekeeper (policy-as-code)
⏳ Phase 4.7 — Falco (runtime threat detection)
⏳ Phase 4.8 — cert-manager + TLS Ingress
⏳ Phase 4.9 — mTLS (order → payment)
⏳ Phase 4.10 — gVisor RuntimeClass
⏳ Phase 4.11 — Vault + External Secrets Operator
```
