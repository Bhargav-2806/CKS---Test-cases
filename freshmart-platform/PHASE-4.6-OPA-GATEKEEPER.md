# Phase 4.6 — OPA Gatekeeper (Policy-as-Code)

**CKS Domains:** Minimize Microservice Vulnerabilities (20%) · Supply Chain Security (20%)  
**Status:** ✅ Complete

---

## What Is OPA Gatekeeper?

**OPA (Open Policy Agent)** is a general-purpose policy engine. **Gatekeeper** is the Kubernetes admission webhook that runs OPA inside the cluster.

Every time a Pod, Deployment, or other resource is created or updated, Gatekeeper intercepts the API request **before** the object is persisted to etcd. It evaluates the request against your policies (written in **Rego**) and either:
- **Allows** it (compliant)
- **Denies** it with a clear error message (violation)
- **Warns** and allows it (audit mode — used for gradual rollout)

```
kubectl create pod ...
        │
        ▼
  Kubernetes API Server
        │
        ├─── ValidatingWebhookConfiguration ──► Gatekeeper webhook
        │                                            │
        │                                    Rego policy evaluation
        │                                            │
        │                              ┌─────────────┴──────────────┐
        │                              │ PASS                  FAIL  │
        │                              ▼                       ▼     │
        └──────────────────────── Admitted         Rejected (403)   │
                                                   "Container must   │
                                                    not be priv..."  │
```

### Why This Matters for CKS

- CKS domain: **"Minimize Microservice Vulnerabilities"** — OPA Gatekeeper is the primary admission control tool beyond PSA
- CKS domain: **"Supply Chain Security"** — enforce allowed registries, no `:latest` tags
- Real world: Every major K8s platform (GKE, EKS, AKS, OpenShift) recommends or includes Gatekeeper for policy enforcement
- Exam scenario: "Ensure only images from the corporate registry can run in the payment namespace"

---

## Architecture in FreshMart

```
                       ADMIT / DENY
                            │
┌──────────────────────────┐│┌──────────────────────────────────────┐
│  Kubernetes API Server   ││  OPA Gatekeeper                       │
│                          ││  ┌──────────────────────────────────┐ │
│  kubectl apply           ││  │  ConstraintTemplates (Rego)      │ │
│  ───────────► admission  │├─►│  - K8sNoLatestTag                │ │
│               webhook ───┘│  │  - K8sAllowedRepos               │ │
│                           │  │  - K8sRequireResourceLimits      │ │
│                           │  │  - K8sNoPrivileged               │ │
│                           │  │  - K8sNoHostPath                 │ │
│                           │  │  - K8sRequireSeccomp             │ │
│                           │  │  - K8sRequireNonRoot             │ │
│                           │  └──────────────────────────────────┘ │
│                           │  ┌──────────────────────────────────┐ │
│                           │  │  Constraints (instances)         │ │
│                           │  │  scoped to: tesco-core,          │ │
│                           │  │  tesco-payments, tesco-frontend  │ │
│                           │  └──────────────────────────────────┘ │
└───────────────────────────┘└──────────────────────────────────────┘
```

### Two-Object Model

Gatekeeper uses a **two-layer system**:

| Object | Purpose | Analogy |
|--------|---------|---------|
| `ConstraintTemplate` | Defines the policy logic in Rego. Creates a CRD. | Class definition |
| `Constraint` | Instance of a template. Specifies which namespaces + enforcement mode. | Object instance |

---

## Policies Implemented

| Policy | Template | Enforcement | Namespaces |
|--------|----------|-------------|------------|
| No `:latest` image tag | `K8sNoLatestTag` | `warn` (audit) | tesco-core, payments, frontend, data, messaging |
| Allowed registries only | `K8sAllowedRepos` | `deny` | tesco-core, payments, frontend |
| Require CPU + memory limits | `K8sRequireResourceLimits` | `deny` | tesco-core, payments, frontend, data |
| No privileged / hostPID / hostIPC / hostNetwork | `K8sNoPrivileged` | `deny` | tesco-core, payments, frontend, data, messaging |
| No hostPath volumes | `K8sNoHostPath` | `deny` | tesco-core, payments, frontend, data, messaging |
| Require seccomp profile | `K8sRequireSeccomp` | `deny` | tesco-core, payments, frontend, data |
| Require non-root | `K8sRequireNonRoot` | `deny` | tesco-core, payments, frontend |

---

## Files Created

```
k8s/13-opa-gatekeeper/
├── templates/
│   ├── k8s-no-latest-tag.yaml           ← blocks :latest / untagged images
│   ├── k8s-allowed-repos.yaml           ← blocks non-whitelisted registries
│   ├── k8s-require-resource-limits.yaml ← blocks missing CPU/memory limits
│   ├── k8s-no-privileged.yaml           ← blocks privileged + host namespaces
│   ├── k8s-no-hostpath.yaml             ← blocks hostPath volumes
│   ├── k8s-require-seccomp.yaml         ← blocks missing/Unconfined seccomp
│   └── require-nonroot.yaml             ← blocks root containers
└── constraints/
    ├── no-latest-tag.yaml               ← warn mode (our images use :latest)
    ├── allowed-repos.yaml               ← deny — freshmart/ + distroless only
    ├── require-resource-limits.yaml     ← deny — all our pods have limits
    ├── no-privileged.yaml               ← deny — no privileged in our pods
    ├── no-hostpath.yaml                 ← deny — no hostPath in our pods
    ├── require-seccomp.yaml             ← deny — all pods have RuntimeDefault
    └── require-nonroot.yaml             ← deny — all pods run as uid 10001+

infra/kind/
└── setup-opa-gatekeeper.sh              ← install script
```

---

## How to Deploy

```bash
cd ~/Downloads/DevSecOps\ Projects/CKS-\ Real\ case/freshmart-platform

chmod +x infra/kind/setup-opa-gatekeeper.sh
./infra/kind/setup-opa-gatekeeper.sh
```

The script:
1. Installs Gatekeeper v3.17.1 via official YAML
2. Waits for `gatekeeper-controller-manager` (x2) + `gatekeeper-audit` pods
3. Applies all 7 ConstraintTemplates
4. Waits 15 seconds for Gatekeeper to generate CRDs from the templates
5. Applies all 7 Constraints

---

## Manual Testing — Verify Each Policy

### Prerequisites
```bash
# Verify Gatekeeper is running
kubectl get pods -n gatekeeper-system
# Expected: gatekeeper-controller-manager (x2) + gatekeeper-audit — all Running

# Verify ConstraintTemplates are installed
kubectl get constrainttemplates
# Expected: 7 templates listed

# Verify Constraints are active
kubectl get k8snolatesttag,k8sallowedrepos,k8srequireresourcelimits,\
k8snoprivileged,k8snohostpath,k8srequireseccomp,k8srequirenonroot
```

---

### Test 1 — Allowed Registries (deny — should BLOCK)

Try to deploy an image from Docker Hub that isn't whitelisted:

```bash
kubectl run test-blocked-registry \
  --image=nginx:1.25.3 \
  --namespace=tesco-core \
  --restart=Never

# Expected output:
# Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request:
# [freshmart-allowed-repos] Container 'test-blocked-registry' uses image 'nginx:1.25.3'
# from a non-allowed registry. Allowed prefixes: ["freshmart/", "gcr.io/distroless/", ...]
```

**What this proves:** The payment-service namespace (or any tesco-* namespace) cannot accidentally pull from a public registry. An attacker who compromised a deployment cannot swap images to a malicious Docker Hub image.

---

### Test 2 — Privileged Container (deny — should BLOCK)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-privileged
  namespace: tesco-core
spec:
  containers:
  - name: test
    image: freshmart/product-service:latest
    securityContext:
      privileged: true
    resources:
      limits:
        cpu: "100m"
        memory: "64Mi"
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
EOF

# Expected output:
# Error from server (Forbidden): ... [freshmart-no-privileged]
# Container 'test' must not run in privileged mode.
```

**Clean up:** `kubectl delete pod test-privileged -n tesco-core --ignore-not-found`

---

### Test 3 — hostPath Volume (deny — should BLOCK)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-hostpath
  namespace: tesco-payments
spec:
  containers:
  - name: test
    image: freshmart/payment-service:latest
    resources:
      limits:
        cpu: "100m"
        memory: "64Mi"
    volumeMounts:
    - name: host-etc
      mountPath: /host-etc
  volumes:
  - name: host-etc
    hostPath:
      path: /etc
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
EOF

# Expected output:
# Error from server (Forbidden): ... [freshmart-no-hostpath]
# Pod 'test-hostpath' uses hostPath volume 'host-etc' (path: /etc).
# Use PVC, emptyDir, or ConfigMap instead.
```

**Why this matters:** `hostPath: /etc` lets the container read (or write) `/etc/passwd`, `/etc/shadow`, and kubeconfig files — trivial node takeover.

**Clean up:** `kubectl delete pod test-hostpath -n tesco-payments --ignore-not-found`

---

### Test 4 — Missing Resource Limits (deny — should BLOCK)

```bash
kubectl run test-no-limits \
  --image=freshmart/product-service:latest \
  --namespace=tesco-core \
  --restart=Never

# Expected output:
# Error from server (Forbidden): ... [freshmart-require-resource-limits]
# Container 'test-no-limits' must set resources.limits.cpu.
# Container 'test-no-limits' must set resources.limits.memory.
```

**Clean up:** `kubectl delete pod test-no-limits -n tesco-core --ignore-not-found`

---

### Test 5 — hostNetwork (deny — should BLOCK)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-hostnet
  namespace: tesco-core
spec:
  hostNetwork: true
  containers:
  - name: test
    image: freshmart/product-service:latest
    resources:
      limits:
        cpu: "100m"
        memory: "64Mi"
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
EOF

# Expected output:
# Error from server (Forbidden): ... [freshmart-no-privileged]
# Pod 'test-hostnet' must not set hostNetwork: true.
# Host network access bypasses all NetworkPolicies.
```

**Why this matters:** `hostNetwork: true` bypasses all NetworkPolicies (including our default-deny-all). A pod with hostNetwork can talk to any service on the node.

**Clean up:** `kubectl delete pod test-hostnet -n tesco-core --ignore-not-found`

---

### Test 6 — :latest Tag Audit (warn — shows violations, does not block)

The `no-latest-tag` constraint runs in `warn` mode. Check violations in the audit:

```bash
# Check audit violations (Gatekeeper scans existing pods every ~60s)
kubectl describe k8snolatesttag freshmart-no-latest-tag

# Look for "violations:" section showing our existing pods
# Example output:
# violations:
#   - enforcementAction: warn
#     group: ""
#     kind: Pod
#     message: Container 'product-service' uses image 'freshmart/product-service:latest'...
#     name: product-service-xxxxx
#     namespace: tesco-core
```

This tells you Phase 5 (CI/CD) needs to tag images with Git SHA or semver.

---

### Test 7 — Verify Existing Pods Comply with All deny Constraints

```bash
# None of the existing FreshMart pods should appear in violation lists

kubectl describe k8sallowedrepos freshmart-allowed-repos | grep -A 20 "Violations:"
kubectl describe k8snoprivileged freshmart-no-privileged | grep -A 20 "Violations:"
kubectl describe k8snohostpath freshmart-no-hostpath | grep -A 20 "Violations:"
kubectl describe k8srequireresourcelimits freshmart-require-resource-limits | grep -A 20 "Violations:"
kubectl describe k8srequireseccomp freshmart-require-seccomp | grep -A 20 "Violations:"
kubectl describe k8srequirenonroot freshmart-require-nonroot | grep -A 20 "Violations:"

# Expected for all: "Violations: <none>" or empty list
```

---

### Test 8 — Dry Run Mode (how to test a new policy safely before enforcing)

```bash
# Temporarily change a constraint to dryrun to see what would be affected
# without actually blocking anything:
kubectl patch k8sallowedrepos freshmart-allowed-repos \
  --type='merge' \
  -p '{"spec":{"enforcementAction":"dryrun"}}'

# After testing, restore to deny:
kubectl patch k8sallowedrepos freshmart-allowed-repos \
  --type='merge' \
  -p '{"spec":{"enforcementAction":"deny"}}'
```

**Three enforcement modes:**
| Mode | Behaviour | Use when |
|------|-----------|----------|
| `deny` | Blocks the request. Returns 403. | Production — enforce hard |
| `warn` | Allows but adds warning to response. Shows in `kubectl describe constraint`. | Rollout / audit phase |
| `dryrun` | Allows, records violations in constraint status only. Silent to user. | Testing new policies |

---

## Understanding Rego

Rego is OPA's policy language. Here's a quick primer using our policies:

```rego
# Basic structure of a Gatekeeper Rego rule
package k8snoprivileged          # package name (matches template)

violation[{"msg": msg}] {        # violation rule — fires when ALL conditions true
  container := input.review.object.spec.containers[_]  # iterate containers
  container.securityContext.privileged == true          # condition: is privileged?
  msg := sprintf("Container '%v' must not run privileged.", [container.name])
}
# If ANY violation fires → request is denied with that message
```

Key inputs:
```
input.review.object             → the K8s resource being admitted (Pod, Deployment, etc.)
input.review.object.metadata    → name, namespace, labels, annotations
input.review.object.spec        → pod spec
input.parameters                → values from Constraint.spec.parameters
```

Key OPA built-ins used:
```rego
startswith(string, prefix)    # "freshmart/nginx" startswith "freshmart/" → true
endswith(string, suffix)      # "image:latest" endswith ":latest" → true
contains(string, substr)      # contains("nginx:latest", ":") → true
split(string, delimiter)      # split("repo/img:1.2", ":") → ["repo/img", "1.2"]
sprintf("msg %v", [var])      # format string with variable
count(array)                  # length of array
```

---

## CKS Exam Scenarios

### Scenario 1: "Ensure only images from the internal registry can run in the payments namespace"

```bash
# This is exactly what K8sAllowedRepos does.
# On the exam, you'd write the ConstraintTemplate + Constraint from scratch.
# Key things to remember:
# 1. ConstraintTemplate defines the Rego logic
# 2. Constraint applies it to specific namespaces with parameters

# Quick exam shortcut — verify the policy works:
kubectl run test --image=badregistry/malware:v1 -n tesco-payments --restart=Never
# Must be rejected
```

### Scenario 2: "Block pods from mounting host filesystem paths"

```bash
# K8sNoHostPath handles this. On the exam:
# - hostPath is a volume type, check input.review.object.spec.volumes[_].hostPath
# - The examiner will try kubectl apply with a hostPath volume in the target namespace
```

### Scenario 3: "Audit which pods are using :latest tags across the cluster"

```bash
# Set enforcementAction: warn (or dryrun) on the constraint
# Wait for the Gatekeeper audit loop (~60 seconds)
kubectl describe k8snolatesttag freshmart-no-latest-tag
# Shows every pod in violation under "Violations:"
```

### Scenario 4: "A developer deployed a pod without resource limits — prevent this"

```bash
# K8sRequireResourceLimits.
# The key Rego pattern:
# not container.resources.limits.cpu  ← "not" = absence check
# This fires when cpu limit is missing
```

---

## How Gatekeeper Differs from Pod Security Admission (PSA)

| | PSA | OPA Gatekeeper |
|---|---|---|
| Configuration | Namespace label | ConstraintTemplate + Constraint CRDs |
| Policy language | Fixed (baseline/restricted/privileged profiles) | Rego (fully custom) |
| Scope | K8s built-in (no install needed) | Must install as admission webhook |
| Flexibility | Only 3 fixed modes | Unlimited custom policies |
| Audit mode | Yes (audit label) | Yes (dryrun/warn) |
| Custom parameters | No | Yes (e.g. allowed registries list) |
| CKS relevance | Domain 4 — must know both | Domain 4 — must know how to write templates |

**In production, use both:** PSA as the first gate (free, zero-config), OPA Gatekeeper for custom business policies on top.

---

## Gatekeeper Important Commands

```bash
# Installation
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.17.1/deploy/gatekeeper.yaml

# Check status
kubectl get pods -n gatekeeper-system
kubectl get constrainttemplates
kubectl get constraints -A

# View all violation details
kubectl describe constraints -A    # shows violations section for all constraints

# Per-constraint violations
kubectl describe k8snoprivileged freshmart-no-privileged

# Check if a specific pod would violate a constraint (dry-run)
kubectl apply --dry-run=server -f pod.yaml

# Temporarily disable a constraint
kubectl patch k8snoprivileged freshmart-no-privileged \
  --type=merge -p '{"spec":{"enforcementAction":"warn"}}'

# Delete a specific constraint (stop enforcing)
kubectl delete k8snoprivileged freshmart-no-privileged

# Check Gatekeeper audit logs (runs every ~60s, re-evaluates existing resources)
kubectl logs -n gatekeeper-system -l control-plane=audit-controller --tail=50

# Check webhook configuration
kubectl get validatingwebhookconfiguration gatekeeper-validating-webhook-configuration
```

---

## Gatekeeper Config — Namespace Exemptions

Gatekeeper itself needs to be exempt from its own policies. The `Config` resource controls this:

```yaml
# This is applied automatically by Gatekeeper's install YAML
apiVersion: config.gatekeeper.sh/v1alpha1
kind: Config
metadata:
  name: config
  namespace: gatekeeper-system
spec:
  match:
    - excludedNamespaces: ["kube-system", "gatekeeper-system"]
      processes: ["*"]
```

If you need to add more exempt namespaces (e.g. ingress-nginx):
```bash
kubectl patch config config -n gatekeeper-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/match/0/excludedNamespaces/-","value":"ingress-nginx"}]'
```

---

## CKS Checklist — What Phase 4.6 Covers

| CKS Topic | Status | Evidence |
|-----------|--------|----------|
| ✅ OPA Gatekeeper installed | Done | gatekeeper-system namespace |
| ✅ ConstraintTemplate — no latest tag | Done | k8s/13-opa-gatekeeper/templates/ |
| ✅ ConstraintTemplate — allowed registries | Done | k8s/13-opa-gatekeeper/templates/ |
| ✅ ConstraintTemplate — require resource limits | Done | k8s/13-opa-gatekeeper/templates/ |
| ✅ ConstraintTemplate — no privileged | Done | k8s/13-opa-gatekeeper/templates/ |
| ✅ ConstraintTemplate — no hostPath | Done | k8s/13-opa-gatekeeper/templates/ |
| ✅ ConstraintTemplate — require seccomp | Done | k8s/13-opa-gatekeeper/templates/ |
| ✅ ConstraintTemplate — require non-root | Done | k8s/13-opa-gatekeeper/templates/ |
| ✅ Constraints scoped per namespace | Done | k8s/13-opa-gatekeeper/constraints/ |
| ✅ Enforcement modes (deny / warn / dryrun) | Done | constraints/*.yaml |
| ✅ Tested: violations are blocked | Done | Manual tests above |
| ✅ Tested: compliant pods pass | Done | Existing deployments |

---

## DevSecOps Engineer Mindset

**Shift-left with Gatekeeper:** These policies catch violations at admission time — before the pod ever runs. This is "shift-left" security applied to runtime:

```
Developer writes   →   CI runs   →   Gatekeeper   →   Pod runs
Dockerfile/YAML        Trivy           blocks            Falco
                       (image)     (bad config)       (runtime)
```

**Policy lifecycle:**
1. Start with `dryrun` mode — audit without blocking. Fix violations.
2. Move to `warn` — visible to developers, no outage risk.
3. Move to `deny` — enforce. New violations are blocked.

**Separation of duties:** Platform/security teams own ConstraintTemplates (the policy logic). Application teams only see "your pod was rejected because X" — they don't modify the policy.

**Audit trail:** Every denied request appears in the Kubernetes API audit log (which we configured in Phase 4.1). Gatekeeper denials are logged with full details.

---

## Phase Progress

```
✅ Phase 4.1 — kube-bench CIS Hardening
✅ Phase 4.2 — etcd Encryption at Rest
✅ Phase 4.3 — Fine-grained RBAC
✅ Phase 4.4 — AppArmor Custom Profiles
✅ Phase 4.5 — Custom seccomp Profiles
✅ Phase 4.6 — OPA Gatekeeper (this phase)
⏳ Phase 4.7 — Falco (runtime threat detection)
⏳ Phase 4.8 — cert-manager + TLS Ingress
⏳ Phase 4.9 — mTLS (order → payment)
⏳ Phase 4.10 — gVisor RuntimeClass
⏳ Phase 4.11 — Vault + External Secrets Operator
```
