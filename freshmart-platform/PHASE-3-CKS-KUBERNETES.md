# Phase 3 — FreshMart CKS: Kubernetes Foundation

> **Project:** FreshMart — A real-world e-commerce platform used as a hands-on CKS (Certified Kubernetes Security Specialist) study project and DevSecOps portfolio.  
> **Phase:** 3 of 8 — Local Kubernetes cluster setup with security-first foundations.  
> **Cluster:** Kind (Kubernetes in Docker) — 1 control-plane + 2 workers.

---

## Table of Contents

1. [What Is Phase 3?](#what-is-phase-3)
2. [Architecture Overview](#architecture-overview)
3. [What We're Trying to Achieve](#what-were-trying-to-achieve)
4. [The DevSecOps Mindset](#the-devsecops-mindset)
5. [Cluster Design](#cluster-design)
6. [Namespace Strategy](#namespace-strategy)
7. [File-by-File Deep Dive](#file-by-file-deep-dive)
8. [Traffic Flow](#traffic-flow)
9. [Security Posture Analysis](#security-posture-analysis)
10. [CKS Domain Coverage](#cks-domain-coverage)
11. [How to Deploy](#how-to-deploy)
12. [Verification & Testing](#verification--testing)
13. [CKS Checklist — Phase 3 Status](#cks-checklist--phase-3-status)
14. [What Phase 4 Adds](#what-phase-4-adds)
15. [Real-World Scenarios & Use Cases](#real-world-scenarios--use-cases)

---

## What Is Phase 3?

Phase 3 takes everything built in Phases 1–2 (the FreshMart frontend + 4 backend microservices) and deploys it into a **production-like Kubernetes cluster** with a security-first approach.

The core philosophy: **security is not bolted on at the end — it is built into every manifest from line 1.**

| Phase | Focus | Output |
|-------|-------|--------|
| 1 | Frontend (Next.js) | FreshMart website |
| 2 | Backend services (Python/Go) | 4 microservices + Docker images |
| **3** | **K8s foundation + CKS security layer** | **Kind cluster, all services running** |
| 4 | CKS hardening (AppArmor, Falco, OPA) | Full CKS exam coverage |
| 5 | CI/CD pipeline (GitHub Actions) | Automated security scanning |
| 6 | ArgoCD GitOps | Automated deployment |
| 7 | EKS (AWS) | Cloud-native production cluster |
| 8 | Observability | Prometheus, Grafana, Loki |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Kind Cluster: freshmart-cks                        │
│                        (1 control-plane + 2 workers)                         │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  INTERNET / Browser (localhost:80)                                       │ │
│  └───────────────────────────┬─────────────────────────────────────────────┘ │
│                              │                                                │
│  ┌───────────────────────────▼─────────────────────────────────────────────┐ │
│  │  namespace: ingress-nginx   PSA: privileged                              │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │ │
│  │  │  nginx Ingress Controller                                        │    │ │
│  │  │  Routes: /api/products → 8001 | /api/cart → 8002                │    │ │
│  │  │          /api/orders  → 8003  | /         → 3000                │    │ │
│  │  └──────┬──────────┬──────────┬───────────────────────────────────┘    │ │
│  └─────────│──────────│──────────│────────────────────────────────────────┘ │
│            │          │          │                                            │
│  ┌─────────▼──┐   ┌───▼──────────▼──────────────────────────────────┐      │
│  │tesco-      │   │  tesco-core          PSA: restricted             │      │
│  │frontend    │   │  ┌──────────────┐  ┌──────────┐  ┌──────────┐   │      │
│  │PSA:        │   │  │product-svc   │  │cart-svc  │  │order-svc │   │      │
│  │baseline    │   │  │:8001 ×2      │  │:8002 ×2  │  │:8003 ×2  │   │      │
│  │┌─────────┐ │   │  │uid:10001     │  │uid:10001 │  │uid:10001 │   │      │
│  ││frontend │ │   │  │seccomp:RTD   │  │seccomp   │  │seccomp   │   │      │
│  ││:3000 ×1 │ │   │  └──────┬───────┘  └────┬─────┘  └────┬─────┘   │      │
│  ││uid:65532│ │   └─────────│──────────────│──────────────│──────────┘      │
│  │└─────────┘ │             │              │              │                  │
│  └────────────┘             │              │              │                  │
│                             └──────────────┴──────┬───────┘                  │
│                                                   │                          │
│  ┌────────────────────────────────────────────────▼───────────────────────┐ │
│  │  tesco-payments        PSA: restricted                                  │ │
│  │  ┌────────────────────────────────────────────────────────────────┐    │ │
│  │  │  payment-service:8004 ×1                                        │    │ │
│  │  │  uid:65532  |  distroless/static  |  readOnlyRootFS: true       │    │ │
│  │  │  ★ Only reachable from order-service via NetworkPolicy ★        │    │ │
│  │  └──────────────────────────────────────────────┬─────────────────┘    │ │
│  └────────────────────────────────────────────────┼─────────────────────┘ │
│                                                   │                          │
│  ┌──────────────────────┐  ┌──────────────────────▼──────────────────────┐ │
│  │  tesco-messaging     │  │  tesco-data           PSA: baseline          │ │
│  │  PSA: baseline       │  │  ┌────────────────────────────────────────┐  │ │
│  │  ┌────────────────┐  │  │  │ postgresql StatefulSet (1 replica)     │  │ │
│  │  │ kafka          │  │  │  │ postgres:16-alpine   uid:999            │  │ │
│  │  │ KRaft mode     │◄─┼──┼──│ PVC: 2Gi   Init SQL: all 4 schemas     │  │ │
│  │  │ 1 broker       │  │  │  └────────────────────────────────────────┘  │ │
│  │  └────────────────┘  │  └─────────────────────────────────────────────┘ │
│  └──────────────────────┘                                                    │
│                                                                               │
│  ┌───────────────────────────────────────────────────────────────────────┐   │
│  │  tesco-monitoring   PSA: privileged   (empty — Phase 4: Falco)        │   │
│  └───────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## What We're Trying to Achieve

### The Problem With "Security Later"

In most tutorial projects, security is an afterthought: build first, secure later. This leads to:
- Containers running as root
- Default service accounts with full cluster permissions
- No network isolation between services
- Secrets hardcoded in environment variables
- No resource limits (enabling DoS attacks)

### The Phase 3 Approach

**Every K8s resource is written with CKS exam intent from the start.** Specifically:

1. **Namespaces isolate blast radius** — if one service is compromised, it cannot access services in other namespaces without an explicit NetworkPolicy allow rule.

2. **PSA enforcement prevents insecure pods** — Kubernetes itself will reject any pod that doesn't meet the security standard for its namespace, before it's even scheduled.

3. **ServiceAccounts with zero permissions** — services can't talk to the Kubernetes API unless explicitly granted, preventing privilege escalation via service account tokens.

4. **Default-deny NetworkPolicies** — every namespace defaults to denying all traffic. Traffic is only allowed where explicitly required. The payment-service can only be reached from order-service. Nothing else.

5. **Security contexts per container** — non-root users, no privilege escalation, capabilities dropped, seccomp enabled on every pod.

---

## The DevSecOps Mindset

As a DevSecOps engineer working on CKS projects, these are the mental models you need:

### 1. Think in Threat Models, Not Features

For every resource ask: *"What is the worst that happens if this component is compromised?"*

| Component | Compromise Impact | Mitigation in Phase 3 |
|-----------|------------------|----------------------|
| Frontend | User-facing XSS, data exposure | Isolated namespace, no DB access |
| product-service | Stale product data | Restricted PSA, no payment access |
| order-service | Fraudulent orders | Can only call payment-service, nothing else |
| payment-service | Financial fraud | Zero public ingress, only order-service can reach it |
| PostgreSQL | Full data breach | Network isolated, only app namespaces can connect |

### 2. Principle of Least Privilege — Everywhere

- **At the network level**: NetworkPolicies enforce east-west traffic rules
- **At the API level**: ServiceAccounts with `automountServiceAccountToken: false`
- **At the OS level**: `capabilities: drop: ALL`, `allowPrivilegeEscalation: false`
- **At the filesystem level**: `readOnlyRootFilesystem: true` (payment-service)
- **At the resource level**: CPU/memory limits prevent noisy-neighbour and DoS

### 3. Security Controls Are Layered (Defence in Depth)

No single control is sufficient. Phase 3 implements 4 layers:

```
Layer 1: Pod Security Admission     → prevents insecure pod specs at admission
Layer 2: Security Contexts          → enforces OS-level restrictions inside containers  
Layer 3: NetworkPolicies            → controls east-west traffic between pods
Layer 4: RBAC + ServiceAccounts     → controls API access and token exposure
```

Phase 4 adds 3 more layers:
```
Layer 5: OPA Gatekeeper             → policy-as-code for admission control
Layer 6: AppArmor / Seccomp         → syscall-level filtering
Layer 7: Falco                      → runtime behavioural detection
```

### 4. Immutable Infrastructure Mindset

Containers should be cattle, not pets:
- No `kubectl exec` in production (Falco alerts on this in Phase 4)
- No patching running containers (redeploy from immutable images)
- All config comes from ConfigMaps/Secrets, never hardcoded

### 5. Observability Is a Security Control

You cannot defend what you cannot see:
- `seccompProfile: RuntimeDefault` = K8s writes audit events for suspicious syscalls
- Resource limits = capacity data for anomaly detection
- Readiness/liveness probes = health data for incident response

---

## Cluster Design

### Why Kind for CKS?

| Property | Kind | minikube | kubeadm |
|----------|------|----------|---------|
| Multi-node | ✅ | Limited | ✅ |
| Fast reset | ✅ (seconds) | ✅ | ❌ (minutes) |
| Matches exam env | ✅ | Partial | ✅ |
| Audit log setup | ✅ | Limited | ✅ |
| Cost | Free | Free | VM cost |
| CKS realism | High | Medium | Highest |

Kind gives us a real multi-node cluster (not a single-node simulation) at zero cost, with fast create/destroy cycles.

### Kind Cluster Config Explained

```yaml
# infra/kind/cluster.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: freshmart-cks
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"  # ← tells nginx to land here
    extraPortMappings:
      - containerPort: 80
        hostPort: 80     # ← browser → localhost:80 → Kind control-plane → ingress
      - containerPort: 443
        hostPort: 443
  - role: worker          # worker-1: app workloads
  - role: worker          # worker-2: app workloads (HA via topologySpreadConstraints)
```

**Why `ingress-ready=true` on control-plane?** The ingress-nginx DaemonSet uses a NodeSelector targeting this label. In Kind, control-plane nodes are the easiest to reach from the host via port mappings. In production, ingress runs on dedicated edge nodes.

---

## Namespace Strategy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Namespace          PSA Level    Contents             Why separate?          │
├─────────────────────────────────────────────────────────────────────────────┤
│  ingress-nginx      privileged   nginx controller     Needs host ports       │
│  tesco-frontend     baseline     Next.js frontend     UI isolation           │
│  tesco-core         restricted   product,cart,order   Business logic         │
│  tesco-payments     restricted   payment-service      PCI-like isolation     │
│  tesco-data         baseline     PostgreSQL            Data tier isolation    │
│  tesco-messaging    baseline     Kafka                 Event bus isolation    │
│  tesco-monitoring   privileged   Falco (Phase 4)       Kernel access needed  │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Pod Security Admission (PSA) Levels:**

| Level | What It Enforces |
|-------|-----------------|
| `restricted` | runAsNonRoot, no privilege escalation, seccomp RuntimeDefault, drop ALL caps, no hostPath |
| `baseline` | No privileged containers, no hostPath, no hostNetwork/PID/IPC |
| `privileged` | No restrictions (required for Falco kernel module, ingress host ports) |

**CKS interview answer:** *"Why separate namespaces for payment?"*
> "The payment-service handles financial transactions. By isolating it in `tesco-payments`, its NetworkPolicy can guarantee zero inbound connections except from `order-service`. If any other pod — including a compromised product-service — tries to call payment, it's dropped at the kernel by iptables rules generated from the NetworkPolicy. Kubernetes doesn't even route the packet."

---

## File-by-File Deep Dive

### `k8s/00-namespaces.yaml` — Namespace + PSA Definitions

**What it does:** Creates all 7 namespaces with Pod Security Admission enforcement labels.

**The three PSA labels per namespace:**
```yaml
pod-security.kubernetes.io/enforce: restricted  # ← BLOCKS pod creation if non-compliant
pod-security.kubernetes.io/warn:    restricted  # ← warns in kubectl output
pod-security.kubernetes.io/audit:   restricted  # ← writes to audit log
```

**CKS relevance:** PSA is a built-in K8s admission controller (replaced PodSecurityPolicy in K8s 1.25). The exam tests your ability to configure and understand it. Setting `enforce` means K8s itself rejects non-compliant pods — no external tool needed.

---

### `k8s/01-rbac.yaml` — ServiceAccounts

**What it does:** Creates one dedicated ServiceAccount per service, all with `automountServiceAccountToken: false`.

**Why `automountServiceAccountToken: false` is critical:**

By default, K8s mounts a service account token into every pod at `/var/run/secrets/kubernetes.io/serviceaccount/token`. An attacker who breaks into any container gets this token and can call the Kubernetes API.

With `automountServiceAccountToken: false`:
- No token is mounted
- The container cannot call the K8s API at all
- If the container is compromised, the blast radius is limited to that pod

**CKS exam point:** This is explicitly tested. You'll see questions like "A pod should not have access to the K8s API — remediate this."

---

### `k8s/02-secrets.yaml` — Kubernetes Secrets

**What it does:** Stores the PostgreSQL DATABASE_URL as a K8s Secret in each namespace that needs it.

**Why per-namespace secrets?** K8s Secrets are namespace-scoped. A secret in `tesco-core` is physically inaccessible to pods in `tesco-payments` and vice versa — even if both namespaces are on the same cluster.

**Current state (Phase 3):** Base64-encoded plaintext in YAML. This is acceptable for local development.

**Production state (Phase 4):** Vault + External Secrets Operator. The secret value never exists in Git. Vault holds the actual value, ESO syncs it into K8s at runtime.

**CKS exam point:** "Secrets are base64, not encrypted" is a common gotcha. Phase 4 covers etcd encryption at rest, which is the actual exam requirement.

---

### `k8s/03-configmaps.yaml` — Application Configuration

**What it does:** Stores non-sensitive configuration (ports, service URLs, feature flags) as ConfigMaps.

**The important distinction:**
- ConfigMap = non-sensitive (service URLs, feature flags, ports) → can be in Git
- Secret = sensitive (passwords, API keys, connection strings) → should NOT be in Git

**Inter-service URLs use K8s internal DNS:**
```
http://product-service.tesco-core.svc.cluster.local:8001
       └── service name ──┘└── namespace ──┘        └─ port
```

This is K8s CoreDNS resolution. The format is: `<service>.<namespace>.svc.cluster.local`.

---

### `k8s/04-storage/postgresql.yaml` — PostgreSQL StatefulSet

**What it does:** Deploys a single-replica PostgreSQL 16 with:
- Headless service (stable DNS: `postgresql.tesco-data.svc.cluster.local`)
- PersistentVolumeClaim (2Gi) for durable data storage
- Init SQL mounted from ConfigMap (creates all 4 schemas + seeds products)
- Readiness/liveness probes using `pg_isready`

**Why StatefulSet, not Deployment?**
- StatefulSets give pods stable, predictable names (`postgresql-0`, `postgresql-1`)
- PVCs are created per-pod and persist across restarts
- Pod is only replaced (not randomly rescheduled) on restart
- Critical for databases that need stable network identity

**The `subPath: pgdata` pattern:**
```yaml
mountPath: /var/lib/postgresql/data
subPath: pgdata
```
Without `subPath`, PostgreSQL fails to initialize if the volume directory contains a `lost+found` directory (common on Linux filesystems). Using `subPath` mounts a subdirectory, keeping the root clean.

**CKS relevance:** Secures PostgreSQL with:
- `runAsUser: 999` (postgres user, not root)
- `fsGroup: 999` (volume is owned by postgres user)
- Isolated in `tesco-data` with NetworkPolicy allowing only app namespaces

---

### `k8s/04-storage/kafka.yaml` — Kafka StatefulSet (KRaft Mode)

**What it does:** Deploys a single-broker Kafka 3.7 in KRaft mode (no ZooKeeper).

**Why KRaft mode?** ZooKeeper is deprecated in Kafka 3.x. KRaft (Kafka Raft) is the modern consensus mechanism built directly into Kafka. Single process, simpler setup, no separate ZooKeeper StatefulSet needed.

**KRaft key configuration:**
```yaml
KAFKA_CFG_PROCESS_ROLES: "controller,broker"   # same pod is both controller + broker
KAFKA_CFG_NODE_ID: "0"                         # unique in the cluster
KAFKA_CFG_CONTROLLER_QUORUM_VOTERS: "0@kafka-0.kafka-headless:9093"
```

**Two services for Kafka:**
- `kafka-headless` (ClusterIP: None) — stable per-pod DNS for the broker itself
- `kafka` (ClusterIP) — standard ClusterIP for application connections

---

### `k8s/05-deployments/` — All 5 Service Deployments

Every Deployment follows the same security template. Here's what each field means:

```yaml
spec:
  template:
    spec:
      serviceAccountName: product-service-sa    # dedicated SA
      automountServiceAccountToken: false        # CKS: no API token mounted

      securityContext:                           # POD-LEVEL context
        runAsNonRoot: true                       # PSA restricted: mandatory
        runAsUser: 10001                         # explicit UID (not root)
        fsGroup: 10001                           # volume ownership
        seccompProfile:
          type: RuntimeDefault                   # PSA restricted: mandatory
                                                 # limits syscalls to common set

      containers:
        - securityContext:                       # CONTAINER-LEVEL context
            allowPrivilegeEscalation: false      # PSA restricted: mandatory
            readOnlyRootFilesystem: false        # Phase 4: true + emptyDir
            capabilities:
              drop: ["ALL"]                      # PSA restricted: mandatory
```

**Payment-service is special:**
- `uid: 65532` (distroless `nonroot`)
- `readOnlyRootFilesystem: true` (Go static binary needs NO writes)
- `replicas: 1` (payment idempotency requires careful scaling)
- Based on `gcr.io/distroless/static-debian12` — zero OS attack surface

**topologySpreadConstraints** on product/cart/order (2 replicas each):
```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
```
This guarantees pods spread across worker nodes. If worker-1 fails, worker-2 still has one replica of each service running.

---

### `k8s/06-ingress/ingress.yaml` — nginx Ingress

**What it does:** Single entry point for the entire platform. Routes HTTP traffic to the correct service based on path prefix.

```
Browser → localhost:80 → Kind port mapping → ingress-nginx pod → 
  /api/products* → product-service.tesco-core:8001
  /api/cart*     → cart-service.tesco-core:8002
  /api/orders*   → order-service.tesco-core:8003
  /*             → frontend.tesco-frontend:3000
```

**Why two Ingress objects?**
The API services live in `tesco-core` and the frontend in `tesco-frontend`. An Ingress routes to services within its own namespace. We create one Ingress in each namespace.

**Path priority:** nginx evaluates path rules by length — longer paths win. `/api/products` (12 chars) beats `/` (1 char), so API requests never accidentally hit the frontend.

**CKS relevance:** In Phase 4, TLS termination is added with cert-manager. The Ingress becomes the TLS termination point, and all backend communication is HTTP over the cluster network (or mTLS with a service mesh).

---

### `k8s/07-network-policies/network-policies.yaml` — NetworkPolicies

**The most important security file in Phase 3.**

**Strategy:**
```
1. Create default-deny-all in EVERY namespace
2. Add explicit allow rules only for required traffic
3. If a rule is missing, traffic is silently dropped (fail-closed)
```

**Key isolation rules:**

```
payment-service NetworkPolicy (the critical one):
  Ingress:
    ALLOW FROM: namespace=tesco-core AND pod=order-service, port=8004
    DENY ALL others (including other tesco-core pods like product-service)
  
  Egress:
    ALLOW TO: kube-system:53 (DNS)
    ALLOW TO: tesco-data:5432 (PostgreSQL)
    ALLOW TO: tesco-messaging:9092 (Kafka)
    DENY ALL others
```

This means:
- `product-service` cannot reach `payment-service` — NetworkPolicy blocks it
- `cart-service` cannot reach `payment-service` — NetworkPolicy blocks it
- An external attacker who breaks into `frontend` cannot reach `payment-service`
- Only `order-service` in `tesco-core` with label `app: order-service` can call `payment-service`

**How NetworkPolicies work under the hood:**
NetworkPolicies are implemented by the CNI plugin (Kind uses kindnet/calico). The CNI translates the policy into iptables rules on each node. When a packet arrives at a pod, the kernel checks iptables before even waking the application. If no rule allows the traffic, the packet is dropped at the kernel — no TCP connection established, no application involvement.

---

## Traffic Flow

### Full Checkout Flow in Kubernetes

```
1. Browser → http://localhost/
   nginx ingress → frontend:3000 (tesco-frontend)
   
2. Browser clicks product
   JavaScript fetch → http://localhost/api/products/4
   nginx ingress → product-service:8001 (tesco-core)
   product-service → postgresql:5432 (tesco-data) [NetworkPolicy allows]
   
3. Browser clicks "Add to Cart"  
   JavaScript fetch → http://localhost/api/cart/{session}/items
   nginx ingress → cart-service:8002 (tesco-core)
   cart-service → product-service:8001 [same namespace, NetworkPolicy allows]
   cart-service → postgresql:5432 [NetworkPolicy allows]
   
4. Browser clicks "Place Order"
   JavaScript fetch → http://localhost/api/orders
   nginx ingress → order-service:8003 (tesco-core)
   order-service → cart-service:8002 [get cart items]
   order-service → payment-service:8004 (tesco-payments) [NetworkPolicy: ALLOWED]
   payment-service → postgresql:5432 [store payment record]
   payment-service → kafka:9092 [publish payment.result]
   order-service → cart-service:8002/cart/{session} [clear cart]
   
5. Browser receives order ID → redirects to /order-confirmed/{id}
```

---

## Security Posture Analysis

### What's Protected in Phase 3

| Attack Vector | Protection | Implemented By |
|---------------|------------|----------------|
| Compromised frontend pod calls payment API | Blocked at kernel | NetworkPolicy |
| Container running as root | Rejected by K8s | PSA `restricted` enforce |
| Process inside container calls kernel exploit | Reduced surface | seccomp RuntimeDefault |
| Container writes to read-only FS areas | Blocked by OS | readOnlyRootFilesystem (payment) |
| Pod steals K8s API token | No token mounted | automountServiceAccountToken: false |
| Container escalates privileges | Blocked | allowPrivilegeEscalation: false |
| Container requests raw network capability | Removed | capabilities: drop: ALL |
| Pod consumes all node CPU | Limited | Resource limits |
| Pod hides in plain text network traffic | All internal K8s DNS traffic | Phase 4: mTLS |
| Malicious image from Docker Hub | imagePullPolicy: Never | Kind-loaded images only |

### What's NOT Yet Protected (Phase 4 Adds This)

| Gap | Phase 4 Solution |
|-----|-----------------|
| Custom AppArmor profiles | Per-service AppArmor profiles with deny rules |
| Custom seccomp profiles | Restrictive syscall whitelist for each service |
| No runtime threat detection | Falco with custom rules |
| No admission policy enforcement | OPA Gatekeeper ConstraintTemplates |
| Secrets in plaintext in etcd | etcd EncryptionConfiguration |
| No K8s API audit trail | Audit policy (log all secret access, exec) |
| Images not verified | Cosign + Gatekeeper policy to reject unsigned images |
| No mTLS between services | Istio or manual cert mTLS for order→payment |

---

## CKS Domain Coverage

The CKS exam has 6 domains. Here's the Phase 3 coverage:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CKS DOMAIN COVERAGE — PHASE 3                             │
├──────────────────────────────────┬────────┬──────────────────────────────────┤
│ Domain                           │ Weight │ Phase 3 Coverage                 │
├──────────────────────────────────┼────────┼──────────────────────────────────┤
│ 1. Cluster Setup                 │  10%   │ ████████░░ 60%                   │
│ 2. Cluster Hardening             │  15%   │ ██████░░░░ 40%                   │
│ 3. System Hardening              │  15%   │ ████░░░░░░ 35%                   │
│ 4. Microservice Vulnerabilities  │  20%   │ ██████░░░░ 50%                   │
│ 5. Supply Chain Security         │  20%   │ ████░░░░░░ 30%                   │
│ 6. Monitoring & Runtime Security │  20%   │ █░░░░░░░░░ 10%                   │
└──────────────────────────────────┴────────┴──────────────────────────────────┘
```

### Domain 1: Cluster Setup (10%) — Phase 3: 60% covered

| Topic | Status | File |
|-------|--------|------|
| ✅ NetworkPolicies — default deny | Done | `07-network-policies/` |
| ✅ NetworkPolicies — explicit allow | Done | `07-network-policies/` |
| ✅ Ingress setup | Done | `06-ingress/` |
| ⏳ Ingress TLS (cert-manager) | Phase 4 | — |
| ⏳ CIS Benchmark (kube-bench) | Phase 4 | — |
| ⏳ Protect node metadata endpoint | Phase 4 | — |

### Domain 2: Cluster Hardening (15%) — Phase 3: 40% covered

| Topic | Status | File |
|-------|--------|------|
| ✅ RBAC — dedicated ServiceAccounts | Done | `01-rbac.yaml` |
| ✅ automountServiceAccountToken: false | Done | `01-rbac.yaml` |
| ✅ PSA enforcement (replaces PSP) | Done | `00-namespaces.yaml` |
| ⏳ Restrict anonymous API access | Phase 4 | — |
| ⏳ etcd encryption at rest | Phase 4 | — |
| ⏳ K8s audit policy | Phase 4 | — |
| ⏳ Fine-grained RBAC roles | Phase 4 | — |

### Domain 3: System Hardening (15%) — Phase 3: 35% covered

| Topic | Status | File |
|-------|--------|------|
| ✅ seccompProfile: RuntimeDefault | Done | All Deployments |
| ✅ runAsNonRoot + explicit UID | Done | All Deployments |
| ✅ allowPrivilegeEscalation: false | Done | All Deployments |
| ✅ capabilities: drop ALL | Done | All Deployments |
| ✅ readOnlyRootFilesystem (payment) | Done | `payment-service.yaml` |
| ✅ Minimal base images (distroless) | Done | Dockerfiles |
| ⏳ AppArmor custom profiles | Phase 4 | — |
| ⏳ Custom seccomp profiles | Phase 4 | — |

### Domain 4: Minimize Microservice Vulnerabilities (20%) — Phase 3: 50% covered

| Topic | Status | File |
|-------|--------|------|
| ✅ PSA restricted enforcement | Done | `00-namespaces.yaml` |
| ✅ Security contexts (pod + container) | Done | All Deployments |
| ✅ Resource requests + limits | Done | All Deployments |
| ✅ NetworkPolicy isolation | Done | `07-network-policies/` |
| ✅ payment-service zero public access | Done | Ingress + NetworkPolicy |
| ⏳ OPA Gatekeeper (ConstraintTemplates) | Phase 4 | — |
| ⏳ Vault + External Secrets | Phase 4 | — |
| ⏳ mTLS (order→payment) | Phase 4 | — |
| ⏳ gVisor RuntimeClass (payment) | Phase 4 | — |
| ⏳ Container sandboxing | Phase 4 | — |

### Domain 5: Supply Chain Security (20%) — Phase 3: 30% covered

| Topic | Status | File |
|-------|--------|------|
| ✅ Minimal base images | Done | Dockerfiles (distroless, slim) |
| ✅ Multi-stage builds | Done | All Dockerfiles |
| ✅ Non-root in images (Dockerfile) | Done | All Dockerfiles |
| ✅ imagePullPolicy: Never (local images) | Done | All Deployments |
| ⏳ Trivy image scanning in CI | Phase 5 | — |
| ⏳ Cosign image signing | Phase 5 | — |
| ⏳ OPA Gatekeeper: allowed registries | Phase 4 | — |
| ⏳ OPA Gatekeeper: no latest tag | Phase 4 | — |
| ⏳ SBOM generation | Phase 5 | — |

### Domain 6: Monitoring, Logging & Runtime Security (20%) — Phase 3: 10% covered

| Topic | Status | File |
|-------|--------|------|
| ✅ seccomp reduces syscall noise | Done | All Deployments |
| ✅ Namespace prepared for Falco | Done | `tesco-monitoring` namespace |
| ⏳ Falco install + custom rules | Phase 4 | — |
| ⏳ K8s audit logs | Phase 4 | — |
| ⏳ Immutable containers (all services) | Phase 4 | — |
| ⏳ Behavioural anomaly detection | Phase 4 | — |
| ⏳ Log aggregation (Loki) | Phase 8 | — |

---

## How to Deploy

### Prerequisites

```bash
# Check all tools are installed
kind --version       # ≥ 0.23.0
kubectl version      # ≥ 1.29
docker --version     # ≥ 24.0
```

### Single-Command Deploy

```bash
cd freshmart-platform
chmod +x infra/kind/setup.sh
./infra/kind/setup.sh
```

The script runs in order:
1. Creates the `freshmart-cks` Kind cluster (3 nodes)
2. Builds all 5 Docker images locally
3. Loads images into Kind cluster nodes
4. Installs ingress-nginx controller
5. Applies manifests: namespaces → rbac → secrets → configmaps → storage → deployments → ingress → networkpolicies
6. Waits for PostgreSQL readiness (up to 2 min)
7. Waits for Kafka readiness (up to 3 min — KRaft startup is slower)
8. Waits for all Deployments to be ready
9. Prints summary

**Expected total time:** 8–12 minutes on first run (image builds + K8s scheduling).

### Tear Down

```bash
kind delete cluster --name freshmart-cks
```

---

## Verification & Testing

### Check Everything is Running

```bash
# All pods across all namespaces
kubectl get pods -A

# Expected output:
# ingress-nginx    ingress-nginx-controller-*   Running
# tesco-frontend   frontend-*                   Running
# tesco-core       product-service-* (×2)       Running
# tesco-core       cart-service-* (×2)          Running
# tesco-core       order-service-* (×2)         Running
# tesco-payments   payment-service-*            Running
# tesco-data       postgresql-0                 Running
# tesco-messaging  kafka-0                      Running
```

### Test the API

```bash
# 1. Products
curl http://localhost/api/products | jq '.[0]'

# 2. Add to cart
curl -X POST http://localhost/api/cart/test123/items \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "quantity": 2}'

# 3. Place order
curl -X POST http://localhost/api/orders \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "test123",
    "delivery_address": {"full_name": "Test User", "address_line1": "123 St", "city": "London", "postcode": "SW1A"},
    "payment_details": {"card_number": "4242424242424242", "expiry": "12/27", "cvv": "123"}
  }'
```

### Verify NetworkPolicies Work

```bash
# Try to reach payment-service from product-service (should FAIL)
kubectl exec -n tesco-core deploy/product-service -- \
  wget -T 3 -O- http://payment-service.tesco-payments.svc.cluster.local:8004/health
# Expected: timeout (NetworkPolicy blocks it)

# Try from order-service (should SUCCEED)
kubectl exec -n tesco-core deploy/order-service -- \
  wget -T 3 -O- http://payment-service.tesco-payments.svc.cluster.local:8004/health
# Expected: {"status":"healthy","service":"payment-service"}
```

### Verify PSA is Enforcing

```bash
# Try to deploy a privileged pod into tesco-core (should be REJECTED)
kubectl run test-priv -n tesco-core \
  --image=nginx \
  --overrides='{"spec":{"containers":[{"name":"test","image":"nginx","securityContext":{"privileged":true}}]}}'
# Expected: Error: pods "test-priv" is forbidden: violates PodSecurity "restricted:latest"
```

### Verify Secret is Mounted Correctly

```bash
kubectl exec -n tesco-core deploy/product-service -- \
  env | grep DATABASE
# Expected: DATABASE_URL=postgresql://freshmart:freshmart@postgresql.tesco-data...
```

### Check Service Account Token is NOT Mounted

```bash
kubectl exec -n tesco-core deploy/product-service -- \
  ls /var/run/secrets/kubernetes.io/
# Expected: ls: /var/run/secrets/kubernetes.io/: No such file or directory
```

---

## CKS Checklist — Phase 3 Status

### ✅ COVERED in Phases 1–3

#### Cluster Setup (Domain 1)
- [x] NetworkPolicy: default-deny-all in every namespace
- [x] NetworkPolicy: explicit allow rules (ingress→app, app→DB, order→payment only)
- [x] Ingress: nginx ingress controller with path routing
- [x] Pod Security Admission: configured per namespace
- [ ] Ingress TLS → Phase 4

#### Cluster Hardening (Domain 2)
- [x] ServiceAccounts: one per service, dedicated
- [x] automountServiceAccountToken: false on all ServiceAccounts
- [x] PSA: `restricted` on tesco-core and tesco-payments
- [x] PSA: `baseline` on data/messaging namespaces
- [ ] RBAC fine-grained roles → Phase 4
- [ ] etcd encryption → Phase 4
- [ ] K8s API audit logging → Phase 4
- [ ] Restrict anonymous API access → Phase 4

#### System Hardening (Domain 3)
- [x] seccompProfile: RuntimeDefault on all pods
- [x] runAsNonRoot: true on all pods
- [x] Explicit runAsUser (10001 for Python, 65532 for distroless)
- [x] allowPrivilegeEscalation: false on all containers
- [x] capabilities: drop ALL on all containers
- [x] readOnlyRootFilesystem: true on payment-service
- [x] Minimal base images (distroless/static, python:3.12-slim)
- [x] Multi-stage Dockerfiles (no build tools in runtime image)
- [ ] AppArmor custom profiles → Phase 4
- [ ] Custom seccomp profiles → Phase 4

#### Minimize Microservice Vulnerabilities (Domain 4)
- [x] PSA restricted enforced
- [x] Security contexts at pod AND container level
- [x] Resource requests AND limits on every container
- [x] NetworkPolicy: payment-service only reachable from order-service
- [x] payment-service: zero public ingress route
- [x] Secrets in K8s Secrets (not ConfigMaps or env vars hardcoded)
- [ ] OPA Gatekeeper → Phase 4
- [ ] Vault secrets management → Phase 4
- [ ] mTLS between order→payment → Phase 4
- [ ] gVisor RuntimeClass for payment → Phase 4

#### Supply Chain Security (Domain 5)
- [x] Distroless runtime images (payment, frontend)
- [x] python:3.12-slim runtime images (product, cart, order)
- [x] Multi-stage builds (builder + runner stages)
- [x] Non-root users in Dockerfiles
- [x] imagePullPolicy: Never (pre-loaded images, no public registry pull)
- [ ] Trivy image scanning → Phase 5
- [ ] Cosign image signing → Phase 5
- [ ] Allowed registries OPA policy → Phase 4
- [ ] No `latest` tag policy → Phase 4

#### Monitoring, Logging & Runtime Security (Domain 6)
- [x] seccompProfile reduces syscall surface (prerequisite for Falco)
- [x] tesco-monitoring namespace created with privileged PSA
- [ ] Falco install + custom rules → Phase 4
- [ ] K8s audit policy → Phase 4
- [ ] Immutable containers (all services) → Phase 4
- [ ] Behavioural anomaly detection → Phase 4

---

## What Phase 4 Adds

Phase 4 is the full CKS hardening layer — it takes this cluster from "secure foundation" to "CKS exam ready":

```
Phase 4 Components:
│
├── kube-bench          → CIS Benchmark scan, fix all FAIL items
├── etcd encryption     → EncryptionConfiguration for Secrets at rest  
├── Audit Policy        → K8s API audit log (secret access, exec, deletes)
├── AppArmor profiles   → custom deny-rules per service container
├── Seccomp profiles    → custom syscall whitelist per service
├── OPA Gatekeeper      → ConstraintTemplates: no latest tag, allowed registries,
│                         resource limits required, non-root required
├── Falco               → runtime threat detection with custom rules:
│                         shell in container → alert
│                         unexpected outbound → alert  
│                         sensitive file read → alert
├── mTLS                → certificate-based mutual auth between order→payment
├── gVisor              → RuntimeClass for payment-service (kernel sandbox)
├── Vault               → External Secrets Operator replacing plain K8s Secrets
└── cert-manager        → TLS for Ingress (self-signed for Kind, ACM for EKS)
```

---

## Real-World Scenarios & Use Cases

### Scenario 1: Developer accidentally deploys with root (realistic team mistake)

**Without PSA:**
```bash
kubectl apply -f deployment.yaml  # succeeds even though it's running as root
# Attacker exploits a CVE → root in container → can modify /etc/passwd
```

**With PSA `restricted` in Phase 3:**
```bash
kubectl apply -f deployment.yaml
# Error: pods "myapp" is forbidden: violates PodSecurity "restricted:latest": ...
# runAsNonRoot is required, allowPrivilegeEscalation must be false
```
PSA acts as a safety net for the whole team — even if a developer forgets security context, Kubernetes rejects the pod.

---

### Scenario 2: A compromised product-service tries to access payment data

**Attack path:**
1. Attacker finds an RCE vulnerability in the product-service API
2. Gets shell inside the `product-service` pod
3. Tries to call `http://payment-service.tesco-payments.svc.cluster.local:8004/api/payments`

**Result with Phase 3 NetworkPolicies:**
```
TCP connection attempt → iptables rule on node → DROP
No TCP SYN-ACK → connection timeout
Application is never involved
```

**CKS exam scenario:** "Verify that pod A cannot communicate with pod B. Apply a NetworkPolicy to enforce this."

---

### Scenario 3: Service account token theft

**Without `automountServiceAccountToken: false`:**
```bash
# Attacker inside any pod:
cat /var/run/secrets/kubernetes.io/serviceaccount/token
# Gets a token → can call K8s API → kubectl get secrets -A → gets all secrets
```

**With Phase 3 setting:**
```bash
# Attacker inside any pod:
cat /var/run/secrets/kubernetes.io/serviceaccount/token
# cat: /var/run/secrets/kubernetes.io/serviceaccount/token: No such file or directory
```

---

### Scenario 4: CKS Exam-Style Question Practice

> *"The payment-service pod is running with excessive privileges. Ensure it:*
> *1. Does not run as root*
> *2. Cannot escalate privileges*
> *3. Has a read-only root filesystem*
> *4. Uses RuntimeDefault seccomp"*

**Our payment-service.yaml already passes this:**
```yaml
securityContext:                         # pod level
  runAsNonRoot: true                     # ✅ (1)
  runAsUser: 65532
  seccompProfile:
    type: RuntimeDefault                 # ✅ (4)
containers:
  - securityContext:                     # container level
      allowPrivilegeEscalation: false    # ✅ (2)
      readOnlyRootFilesystem: true       # ✅ (3)
      capabilities:
        drop: ["ALL"]
```

---

*Phase 3 complete. The FreshMart platform runs in a production-like Kubernetes cluster with a security-first foundation across all 6 CKS domains.*

*Next: Phase 4 — CKS Hardening (AppArmor, Seccomp, OPA Gatekeeper, Falco, etcd encryption, Audit Policy).*
