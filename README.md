# FreshMart — CKS & DevSecOps Platform

> A production-grade, security-first Kubernetes e-commerce platform built as a real-world
> reference for the **Certified Kubernetes Security Specialist (CKS)** exam and
> **DevSecOps** engineering roles.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Technology Stack](#3-technology-stack)
4. [Directory Structure](#4-directory-structure)
5. [Quick Start](#5-quick-start)
6. [Phase Progress](#6-phase-progress)
7. [Phase 1 — Frontend](#7-phase-1--frontend)
8. [Phase 2 — Backend Services](#8-phase-2--backend-services)
9. [Phase 3 — Kind Cluster Foundation](#9-phase-3--kind-cluster-foundation)
10. [Phase 4 — CKS Security Layer](#10-phase-4--cks-security-layer)
11. [Pending Phases 5–8](#11-pending-phases-58)
12. [DevSecOps — Zero to Hero Flow](#12-devsecops--zero-to-hero-flow)
13. [CKS Domain Coverage](#13-cks-domain-coverage)
14. [AI in DevSecOps — Real-World Scenarios](#14-ai-in-devsecops--real-world-scenarios)
15. [Production Architecture (EKS)](#15-production-architecture-eks)
16. [Manual Testing Guide](#16-manual-testing-guide)
17. [CKS Exam Preparation](#17-cks-exam-preparation)
18. [Interview Preparation](#18-interview-preparation)
19. [Resources & References](#19-resources--references)

---

## 1. Project Overview

FreshMart is a **Tesco-inspired grocery e-commerce platform** built from the ground up to demonstrate every aspect of **Kubernetes security** and **DevSecOps** in a real production scenario.

### Why This Project Exists

Most CKS study resources show YAML snippets in isolation. This project shows how all security controls work together on a real, running application — with actual services, real network traffic, live databases, and observable security events.

### What Makes It Unique

```
Other CKS projects:         This project:
──────────────────          ──────────────────────────────────────────
YAML files only             Real application with live traffic
Single service              5 microservices in 7 namespaces
Static configs              Dynamic: cert-manager, ESO, Gatekeeper
No application code         Full Go + Python + Next.js services
No CI/CD                    Complete pipeline (Phase 5)
No cloud deployment         EKS migration path (Phase 7)
No AI integration           AI-powered security layer (Phase 4+)
```

### Business Domain: FreshMart Grocery

The platform simulates a real grocery delivery service:
- Customers browse 12 products across categories
- Add items to cart (session-based, PostgreSQL-backed)
- Place orders (full checkout flow)
- Payments processed securely (internal-only service)
- All traffic encrypted (HTTPS + mTLS for internal services)

---

## 2. Architecture

### Service Architecture

```
                        INTERNET
                            │
                     HTTPS :443
                            │
                 ┌──────────▼───────────┐
                 │   nginx Ingress       │  TLS termination
                 │   (ingress-nginx)     │  HSTS, security headers
                 │   cert-manager cert   │  HTTP→HTTPS redirect
                 └──┬───────────┬────────┘
                    │           │
         ┌──────────▼──┐    ┌───▼─────────────────────────────────┐
         │  Frontend    │    │         API Routes                   │
         │  (Next.js)   │    │  /api/products → product-service    │
         │  Port 3000   │    │  /api/cart     → cart-service       │
         │  TypeScript  │    │  /api/orders   → order-service      │
         │  Distroless  │    │  /api/payments → BLOCKED (internal) │
         └─────────────┘    └────────────────────────────────────┘
                                          │
              ┌───────────────────────────┼──────────────────────┐
              │                           │                       │
     ┌────────▼──────┐         ┌──────────▼──────┐   ┌──────────▼──────┐
     │ product-svc   │         │   cart-svc       │   │   order-svc     │
     │ Python FastAPI│         │ Python FastAPI   │   │ Python FastAPI  │
     │ Port 8001     │         │ Port 8002         │   │ Port 8003       │
     │ 2 replicas    │         │ 2 replicas        │   │ 2 replicas      │
     └───────┬───────┘         └────────┬──────────┘   └───────┬─────────┘
             │                          │                       │
             └──────────────────────────┼───────────────────────┘
                                        │ Internal only
                                        │ mTLS (mutual TLS)
                                        │ NetworkPolicy enforced
                               ┌────────▼────────┐
                               │  payment-svc     │
                               │  Go (net/http)   │
                               │  Port 8004       │
                               │  1 replica       │
                               │  distroless/static│
                               │  gVisor sandbox  │
                               └────────┬─────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    │                   │                    │
          ┌─────────▼──────┐   ┌────────▼──────┐   ┌───────▼────────┐
          │  PostgreSQL 16  │   │    Kafka       │   │  HashiCorp     │
          │  (StatefulSet) │   │  (KRaft mode)  │   │  Vault         │
          │  tesco-data     │   │  tesco-msg    │   │  tesco-security│
          └────────────────┘   └───────────────┘   └────────────────┘
```

### Namespace Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster (Kind: freshmart-cks)                                │
│                                                                           │
│  ingress-nginx    → nginx Ingress Controller              PSA: privileged│
│  tesco-frontend   → Next.js Frontend                      PSA: baseline  │
│  tesco-core       → Product, Cart, Order Services         PSA: restricted│
│  tesco-payments   → Payment Service ONLY                  PSA: restricted│
│  tesco-data       → PostgreSQL                            PSA: baseline  │
│  tesco-messaging  → Kafka (KRaft)                         PSA: baseline  │
│  tesco-monitoring → Falco, Prometheus (Phase 4.7, 8)     PSA: privileged│
│  tesco-security   → OPA Gatekeeper, Vault                 PSA: privileged│
│  cert-manager     → cert-manager controllers              PSA: restricted│
│  external-secrets → External Secrets Operator             PSA: restricted│
│  gatekeeper-system→ OPA Gatekeeper webhooks               PSA: privileged│
└─────────────────────────────────────────────────────────────────────────┘
```

### Security Layer Stack

```
Layer         Tool                  What it protects
──────────    ────────────────────  ──────────────────────────────────
Network L3    NetworkPolicy         Pod-to-pod traffic enforcement
Network L4    mTLS                  Order→Payment mutual authentication
Network L7    nginx Ingress TLS     External HTTPS + security headers
Admission     PSA (restricted)      Blocks unsafe pod configs
Admission     OPA Gatekeeper        Policy-as-code (no latest tags, etc.)
Runtime       AppArmor              Kernel capability restrictions
Runtime       seccomp               Syscall allowlist per service
Runtime       gVisor (payment)      Full user-space kernel sandbox
Runtime       Falco                 Behavioural anomaly detection
Storage       etcd encryption       Secrets encrypted at rest (AES-256)
Identity      RBAC                  Least-privilege service accounts
Identity      mTLS client certs     Cryptographic service identity
Secrets       Vault + ESO           Dynamic secrets, zero plaintext in Git
Supply Chain  Distroless images     Zero OS attack surface (payment)
Supply Chain  Multi-stage builds    No build tools in runtime image
```

---

## 3. Technology Stack

### Application

| Service | Language | Base Image | Port |
|---------|----------|-----------|------|
| Frontend | Next.js 15 (TypeScript) | `distroless/nodejs20` | 3000 |
| product-service | Python 3.12 + FastAPI | `python:3.12-slim` multi-stage | 8001 |
| cart-service | Python 3.12 + FastAPI | `python:3.12-slim` multi-stage | 8002 |
| order-service | Python 3.12 + FastAPI | `python:3.12-slim` multi-stage | 8003 |
| payment-service | Go 1.23 (net/http) | `distroless/static-debian12` | 8004 |

### Infrastructure

| Component | Tool | Version | Purpose |
|-----------|------|---------|---------|
| Local K8s | Kind | 0.31.0 | 3-node cluster |
| K8s version | kindest/node | v1.35.0 | Control plane + 2 workers |
| Container runtime | containerd | Latest | OCI runtime |
| Ingress | nginx-ingress | Latest | TLS termination, routing |
| Database | PostgreSQL | 16-alpine | StatefulSet, all schemas |
| Message bus | Kafka (KRaft) | — | Async events |
| Package manager | Helm | 3.x | All infra installs |

### Security Tools

| Tool | Version | Domain |
|------|---------|--------|
| cert-manager | v1.16.2 | TLS lifecycle management |
| OPA Gatekeeper | v3.17.1 | Admission policy-as-code |
| Falco | 0.39+ | Runtime threat detection |
| HashiCorp Vault | Latest (dev) | Secrets management |
| External Secrets Operator | Latest | Vault → K8s Secrets sync |
| gVisor (runsc) | 20240212.0 | Container kernel sandbox |
| kube-bench | Latest | CIS benchmark scanning |

### Planned (Phases 5–8)

| Tool | Phase | Purpose |
|------|-------|---------|
| GitHub Actions | 5 | CI/CD pipeline |
| Trivy | 5 | Container image scanning |
| Cosign (Sigstore) | 5 | Image signing + verification |
| Syft | 5 | SBOM generation |
| Gitleaks | 5 | Secret scanning in commits |
| ArgoCD | 6 | GitOps continuous delivery |
| Terraform | 7 | EKS + VPC + IAM provisioning |
| AWS EKS | 7 | Production Kubernetes |
| AWS ACM | 7 | Managed TLS certificates |
| Prometheus | 8 | Metrics collection |
| Grafana | 8 | Dashboards + alerting |
| Loki | 8 | Log aggregation |
| Falco Sidekick | 8 | Alert routing to Slack/PD |

---

## 4. Directory Structure

```
freshmart-platform/
│
├── services/                       # Application source code
│   ├── frontend/                   # Next.js TypeScript app
│   │   ├── app/                    # Next.js App Router pages
│   │   │   ├── page.tsx            # Homepage (product grid)
│   │   │   ├── products/[id]/      # Product detail
│   │   │   ├── cart/               # Shopping cart
│   │   │   ├── checkout/           # Checkout form
│   │   │   └── order-confirmed/    # Order confirmation
│   │   ├── components/             # Reusable React components
│   │   ├── context/CartContext.tsx # Global cart state
│   │   ├── lib/                    # Types, data, API client
│   │   ├── Dockerfile              # 3-stage: deps→build→distroless
│   │   └── .env.example            # K8s service URL template
│   │
│   ├── product-service/            # Python FastAPI — product catalog
│   │   ├── app/
│   │   │   ├── main.py             # Routes + seeding 12 products
│   │   │   ├── models.py           # SQLAlchemy Product model
│   │   │   ├── schemas.py          # Pydantic request/response
│   │   │   ├── database.py         # PostgreSQL connection pool
│   │   │   └── config.py           # Settings from env vars
│   │   ├── Dockerfile              # Multi-stage, uid 10001
│   │   └── requirements.txt
│   │
│   ├── cart-service/               # Python FastAPI — session cart
│   ├── order-service/              # Python FastAPI — order lifecycle
│   │   └── app/main.py             # includes mTLS client (Phase 4.9)
│   │
│   └── payment-service/            # Go net/http — payment processing
│       ├── main.go                 # mTLS server + payment logic
│       ├── go.mod
│       ├── go.sum
│       └── Dockerfile              # golang:1.23-alpine → distroless/static
│
├── k8s/                            # Kubernetes manifests
│   ├── 00-namespaces.yaml          # 7 namespaces + PSA labels
│   ├── 01-rbac.yaml                # ServiceAccounts + Roles + Bindings
│   ├── 02-secrets.yaml             # Phase 3 plain secrets (replaced by Vault)
│   ├── 03-configmaps.yaml          # Service configuration
│   ├── 04-storage/
│   │   ├── postgresql.yaml         # StatefulSet + PVC + initContainer
│   │   └── kafka.yaml              # KRaft StatefulSet
│   ├── 05-deployments/             # Per-service Deployments + Services
│   ├── 06-ingress/                 # Phase 3 HTTP ingress
│   ├── 07-network-policies/        # default-deny + allow rules
│   ├── 08-audit-policy/            # K8s API audit logging
│   ├── 09-etcd-encryption/         # EncryptionConfiguration
│   ├── 10-rbac-hardening/          # Fine-grained Roles per service
│   ├── 11-apparmor/                # AppArmor profile patches
│   ├── 12-seccomp/                 # Custom seccomp profiles
│   ├── 13-opa-gatekeeper/
│   │   ├── templates/              # 7 ConstraintTemplates (Rego)
│   │   └── constraints/            # 7 Constraints per namespace
│   ├── 14-cert-manager/            # TLS Ingress + certificates
│   ├── 15-mtls/                    # mTLS certs + deployment patches
│   ├── 16-gvisor/                  # RuntimeClass + payment patch
│   └── 17-vault-eso/               # Vault RBAC + SecretStore + ExternalSecrets
│
├── security/                       # Security tool configurations
│   ├── falco/
│   │   ├── falco-values.yaml       # Helm values (modern_ebpf driver)
│   │   └── rules/
│   │       └── freshmart-rules.yaml # 10 custom rules + lists + macros
│   └── vault/
│       └── vault-values.yaml       # Vault dev mode Helm values
│
├── infra/
│   └── kind/
│       ├── cluster.yaml            # Kind cluster: 1 CP + 2 workers
│       ├── setup.sh                # Phase 3 full cluster bootstrap
│       ├── setup-apparmor.sh       # Phase 4.4
│       ├── setup-seccomp.sh        # Phase 4.5
│       ├── setup-opa-gatekeeper.sh # Phase 4.6
│       ├── setup-falco.sh          # Phase 4.7
│       ├── setup-cert-manager.sh   # Phase 4.8
│       ├── setup-mtls.sh           # Phase 4.9
│       ├── setup-gvisor.sh         # Phase 4.10
│       ├── setup-vault-eso.sh      # Phase 4.11
│       ├── patch-control-plane.sh  # Phase 4.1 kube-bench fixes
│       ├── setup-etcd-encryption.sh# Phase 4.2
│       ├── kube-bench-master.yaml  # kube-bench control plane job
│       └── rbac-audit.sh           # Phase 4.3 RBAC audit
│
├── docker-compose.yaml             # Local development (Phase 2)
├── Makefile                        # Build shortcuts
│
└── docs/                           # Phase documentation
    ├── PHASE-3-CKS-KUBERNETES.md
    ├── PHASE-4.1-KUBE-BENCH.md
    ├── PHASE-4.2-ETCD-ENCRYPTION.md
    ├── PHASE-4.3-RBAC.md
    ├── PHASE-4.4-APPARMOR.md
    ├── PHASE-4.5-SECCOMP.md
    ├── PHASE-4.6-OPA-GATEKEEPER.md
    ├── PHASE-4.7-FALCO.md
    ├── PHASE-4.8-CERT-MANAGER-TLS.md
    ├── PHASE-4.9-MTLS.md
    ├── PHASE-4.10-GVISOR.md
    └── PHASE-4.11-VAULT-ESO.md
```

---

## 5. Quick Start

### Prerequisites

```bash
# Required tools
kind    v0.31+
kubectl v1.36+
docker  v24+
helm    v3.14+
```

### Option A — Full Platform (Phase 3 + all Phase 4)

```bash
git clone <repo>
cd freshmart-platform

# 1. Bootstrap Kind cluster + deploy all services
chmod +x infra/kind/setup.sh
./infra/kind/setup.sh

# 2. Apply CKS security layer (run in order)
chmod +x infra/kind/patch-control-plane.sh && ./infra/kind/patch-control-plane.sh
chmod +x infra/kind/setup-etcd-encryption.sh && ./infra/kind/setup-etcd-encryption.sh
chmod +x infra/kind/setup-opa-gatekeeper.sh && ./infra/kind/setup-opa-gatekeeper.sh
chmod +x infra/kind/setup-cert-manager.sh && ./infra/kind/setup-cert-manager.sh
chmod +x infra/kind/setup-mtls.sh && ./infra/kind/setup-mtls.sh
chmod +x infra/kind/setup-gvisor.sh && ./infra/kind/setup-gvisor.sh
chmod +x infra/kind/setup-vault-eso.sh && ./infra/kind/setup-vault-eso.sh

# 3. Add hosts entry
sudo sh -c 'echo "127.0.0.1 freshmart.local" >> /etc/hosts'

# 4. Open in browser
open https://freshmart.local
```

### Option B — Local Development (Docker Compose, Phase 2)

```bash
cd freshmart-platform
docker-compose up -d --build
open http://localhost:3000
```

### Verify Everything Is Running

```bash
kubectl get pods -A
# Expected: all pods Running or Completed

curl -sk https://freshmart.local/api/products | python3 -m json.tool | head -20
# Expected: 12 products from PostgreSQL

curl -I https://freshmart.local
# Expected: HTTP/2 200 + security headers (X-Frame-Options, HSTS, etc.)
```

---

## 6. Phase Progress

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  PROJECT STATUS                                                               │
├────────────────────────────────────────────────────────┬─────────┬──────────┤
│  Phase                                                  │ Status  │  Where   │
├────────────────────────────────────────────────────────┼─────────┼──────────┤
│  Phase 1 — Frontend (Next.js + Stitch design)          │   ✅    │  Kind    │
│  Phase 2 — Backend Services (Go + Python + FastAPI)    │   ✅    │  Kind    │
│  Phase 3 — Kind Cluster + K8s Foundation               │   ✅    │  Kind    │
│  Phase 4.1 — kube-bench CIS Hardening                 │   ✅    │  Kind    │
│  Phase 4.2 — etcd Encryption at Rest                  │   ✅    │  Kind    │
│  Phase 4.3 — Fine-grained RBAC                        │   ✅    │  Kind    │
│  Phase 4.4 — AppArmor Custom Profiles                 │   ✅    │  Kind    │
│  Phase 4.5 — Custom seccomp Profiles                  │   ✅    │  Kind    │
│  Phase 4.6 — OPA Gatekeeper (policy-as-code)          │   ✅    │  Kind    │
│  Phase 4.7 — Falco (runtime threat detection)         │   ⏳    │  EKS     │
│  Phase 4.8 — cert-manager + TLS Ingress               │   ✅    │  Kind    │
│  Phase 4.9 — mTLS (order → payment)                   │   ✅    │  Kind    │
│  Phase 4.10 — gVisor RuntimeClass                     │   ✅    │  Kind    │
│  Phase 4.11 — Vault + External Secrets Operator       │   ✅    │  Kind    │
│  Phase 5 — CI/CD (GitHub Actions + Trivy + Cosign)    │   ⏳    │  GitHub  │
│  Phase 6 — ArgoCD (GitOps)                            │   ⏳    │  Kind    │
│  Phase 7 — EKS (AWS cloud deployment)                 │   ⏳    │  AWS     │
│  Phase 8 — Observability (Prometheus + Grafana + Loki)│   ⏳    │  AWS     │
└────────────────────────────────────────────────────────┴─────────┴──────────┘
```

---

## 7. Phase 1 — Frontend

### What Was Built

A pixel-perfect Next.js 15 grocery store built from Stitch/AI-generated designs:

- **5 pages**: Homepage (product grid), Product Detail, Shopping Cart, Checkout, Order Confirmation
- **Brand**: FreshMart — green `#1B5E20` + orange `#FF6F00`, Inter font
- **Cart state**: React Context + localStorage + backend API sync
- **API layer**: calls product/cart/order services with mock fallback
- **Dockerfile**: 3-stage (deps → build → distroless/nodejs20) — no shell, no OS

### Key Technical Decisions

```
React 18.3.1 (not 19 — breaking changes)
Next.js 15.4.11 (not 15.3.x — had CVE-2025-66478)
Tailwind CSS 3.4.17 (v3 — v4 is a complete rewrite)
TypeScript 5.7.3
Node.js 20 (LTS)
```

### CKS Relevance

The distroless Node image demonstrates Supply Chain Security:
- No shell (`/bin/sh`) — `kubectl exec pod -- /bin/sh` fails
- No package manager — attacker cannot install tools post-exploit
- Non-root uid 65532 — cannot write to most filesystem paths
- Multi-stage build — build tools (node_modules) not in runtime image

---

## 8. Phase 2 — Backend Services

### Services Built

#### payment-service (Go 1.23) — CKS Showpiece

The most security-hardened service in the platform.

```go
// mTLS enforcement (Phase 4.9)
tlsConfig := &tls.Config{
    ClientAuth:   tls.RequireAndVerifyClientCert,  // mutual TLS
    ClientCAs:    caPool,                           // verify against our CA
    MinVersion:   tls.VersionTLS12,
    VerifyPeerCertificate: func(_, chains ...) error {
        cn := chains[0][0].Subject.CommonName
        if cn != "order-service" { return fmt.Errorf("unauthorized: %s", cn) }
        return nil  // only order-service may call payment-service
    },
}
```

Image: `gcr.io/distroless/static-debian12` — static Go binary + nothing else. Zero OS, zero shell, zero package manager.

#### order-service / product-service / cart-service (Python FastAPI)

Uniform pattern across all three:
- Python 3.12-slim → multi-stage → distroless runtime
- SQLAlchemy 2.0 (not deprecated `bulk_insert_mappings`)
- Pydantic v2 settings
- mTLS client in order-service (Phase 4.9)

### Version Policy

All dependencies pinned to stable, non-CVE versions:

| Package | Version | Reason |
|---------|---------|--------|
| FastAPI | 0.115.14 | 3 minors behind latest |
| SQLAlchemy | 2.0.36 | Proven 2.0.x series |
| Go | 1.23 | LTS line |
| Python base | 3.12-slim | LTS, not 3.13 |

---

## 9. Phase 3 — Kind Cluster Foundation

### Cluster Setup

```yaml
# 3-node Kind cluster
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80    # HTTP
        hostPort: 80
      - containerPort: 443   # HTTPS
        hostPort: 443
  - role: worker
  - role: worker
```

### What Was Deployed

```
✅ 7 namespaces with PSA enforcement labels
✅ 7 ServiceAccounts (automountServiceAccountToken: false)
✅ PostgreSQL StatefulSet (16-alpine, initContainer for PVC permissions)
✅ Kafka StatefulSet (KRaft mode, no ZooKeeper)
✅ 5 application Deployments + ClusterIP Services
✅ nginx Ingress Controller
✅ NetworkPolicies: default-deny-all + explicit allow rules
✅ All pods: runAsNonRoot, drop ALL capabilities, seccompProfile: RuntimeDefault
```

### Network Policy Design

```
default-deny-all in every app namespace
       │
       ▼ allows:
  ingress-nginx → tesco-frontend (port 3000)
  ingress-nginx → tesco-core (ports 8001, 8002, 8003)
  tesco-core → tesco-data (port 5432)
  tesco-core (order-service) → tesco-payments (port 8004) ← only order-service
  tesco-payments → tesco-data (port 5432)
  ALL ELSE → DENIED (kernel-level, no route)
```

Payment-service has **zero public ingress** — no Ingress route to `/api/payments`. Only `order-service` can reach it, enforced by NetworkPolicy.

---

## 10. Phase 4 — CKS Security Layer

### 4.1 — kube-bench CIS Hardening

**What it does**: Scans the cluster against CIS Kubernetes Benchmark v1.8.

**Before fixes**: 63 PASS · 12 FAIL · 50 WARN
**After fixes**: 74 PASS · 1 FAIL · 50 WARN

**Fixes applied via `patch-control-plane.sh`**:

```bash
# API server hardening
--profiling=false                           # Disable profiling endpoint
--audit-log-path=/var/log/apiserver/audit.log
--audit-log-maxage=30
--audit-log-maxbackup=10
--audit-log-maxsize=100
--service-account-extend-token-expiration=false
--kubelet-certificate-authority=/etc/kubernetes/pki/ca.crt

# Controller manager + scheduler
--profiling=false   # On both

# etcd ownership
chown etcd:etcd /var/lib/etcd
```

**1 remaining FAIL**: `1.2.5 kubelet-certificate-authority` — Kind environment limitation (not a real kubeadm cluster).

**CKS exam tip**: The audit log flags (1.2.16–19) are the most commonly tested. Know all 4: `audit-log-path`, `audit-log-maxage`, `audit-log-maxbackup`, `audit-log-maxsize`.

---

### 4.2 — etcd Encryption at Rest

**What it does**: Encrypts all Kubernetes Secrets in etcd using AES-256 (aescbc).

**Before** (Phase 3 — plaintext in etcd):
```bash
kubectl exec etcd-pod -- etcdctl get /registry/secrets/tesco-core/db-credentials
# → v1Secret...DATABASE_URL...postgresql://freshmart:freshmart@... ← READABLE
```

**After** (Phase 4.2 — encrypted):
```bash
# Same command returns:
# → k8s:enc:aescbc:v1:freshmart-key-1:Ω∂ƒ¬˚∆©≈ç (garbled binary)
```

**Critical step most people miss**: After enabling encryption, you must re-encrypt ALL existing Secrets:
```bash
kubectl get secrets --all-namespaces -o json | kubectl replace -f -
```

Without this, only NEW Secrets are encrypted. Old ones stay plaintext.

**EncryptionConfiguration**:
```yaml
resources:
  - resources: ["secrets", "configmaps"]
    providers:
      - aescbc:
          keys:
            - name: freshmart-key-1
              secret: <32-byte-base64-key>
      - identity: {}    # fallback for reading old unencrypted data
```

---

### 4.3 — Fine-grained RBAC

**What it does**: Replaces broad ServiceAccount permissions with least-privilege Roles.

**Before** (Phase 3 — no roles, just ServiceAccounts):
- ServiceAccounts existed but had no explicit permissions
- Default ServiceAccount had no binding — fine, but no explicit deny

**After** (Phase 4.3):
```yaml
# Each service gets exactly what it needs — nothing more
# product-service: read ConfigMaps in its namespace only
# payment-service: no K8s API access at all (automountServiceAccountToken: false)
# order-service: read Secrets for DB creds only
```

**RBAC audit**:
```bash
# Check what every service account can do
kubectl auth can-i --list --as=system:serviceaccount:tesco-core:order-service-sa
# Should show minimal permissions

# Check for dangerous cluster-wide permissions
kubectl get clusterrolebindings -o json | \
  jq '.items[] | select(.subjects[]?.name != "system:") | .metadata.name'
```

---

### 4.4 — AppArmor Custom Profiles

**What it does**: Per-container kernel capability restrictions loaded as AppArmor profiles on Kind nodes.

**AppArmor profiles**: Kernel-level MAC (Mandatory Access Control) rules that restrict:
- Which files a process can read/write/execute
- Which network operations are permitted
- Which capabilities can be used
- Which syscalls can be called (overlaps with seccomp)

**Profile for payment-service** (strictest):
```
# deny ALL file writes except /tmp
deny /etc/** w,
deny /usr/** w,
deny /bin/** w,

# deny shell execution
deny /bin/sh mrix,
deny /bin/bash mrix,

# allow only necessary network
network tcp,
deny network raw,
deny network packet,
```

**Applied via annotation** (Kubernetes 1.30+ uses pod spec field):
```yaml
annotations:
  container.apparmor.security.beta.kubernetes.io/payment-service: localhost/freshmart-payment
```

---

### 4.5 — Custom seccomp Profiles

**What it does**: Per-service syscall allowlists (whitelist-based filtering).

**Difference from AppArmor**:
- AppArmor: restricts what the process can access (files, network, capabilities)
- seccomp: restricts which kernel system calls the process can make

**Our seccomp profiles** (JSON format on Kind nodes at `/var/lib/kubelet/seccomp/`):

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "syscalls": [
    {
      "names": ["read", "write", "open", "close", "stat", "fstat",
                "mmap", "mprotect", "munmap", "brk", "rt_sigaction",
                "connect", "accept", "socket", "bind", "listen",
                "getpid", "clone", "futex", "nanosleep", "exit_group"],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

Payment-service allows ~35 syscalls. The default Linux kernel exposes ~400. Attack surface reduced by 90%+.

**Applied via pod spec**:
```yaml
securityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: freshmart/payment-service.json
```

---

### 4.6 — OPA Gatekeeper

**What it does**: Kubernetes admission webhook that enforces custom policies written in Rego.

**7 ConstraintTemplates deployed**:

| Template | Mode | Blocks |
|----------|------|--------|
| K8sNoLatestTag | warn | `:latest` or untagged images |
| K8sAllowedRepos | deny | Images from non-whitelisted registries |
| K8sRequireResourceLimits | deny | Containers without CPU/memory limits |
| K8sNoPrivileged | deny | `privileged:true`, hostPID, hostIPC, hostNetwork |
| K8sNoHostPath | deny | hostPath volume mounts |
| K8sRequireSeccomp | deny | Missing or `Unconfined` seccomp |
| K8sRequireNonRoot | deny | Root containers |

**How a constraint blocks a pod**:
```bash
kubectl run test --image=nginx:latest -n tesco-core --restart=Never
# Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request:
# [freshmart-no-latest-tag] Container 'test' uses ':latest' image tag
# [freshmart-allowed-repos] Container 'test' uses image 'nginx:latest' from a non-allowed registry
```

**Rego policy example**:
```rego
package k8snohostpath

violation[{"msg": msg}] {
  volume := input.review.object.spec.volumes[_]
  volume.hostPath               # hostPath volume exists
  msg := sprintf(
    "Pod '%v' uses hostPath volume '%v' (path: %v). Use PVC instead.",
    [input.review.object.metadata.name, volume.name, volume.hostPath.path]
  )
}
```

---

### 4.7 — Falco (Runtime Threat Detection)

**Status**: Rules written, Helm values configured. **Deployment deferred to EKS Phase 7** — gVisor eBPF driver requires real EC2 nodes (no nested VM support in Docker Desktop).

**10 Custom FreshMart Rules**:

| Rule | Priority | Detects |
|------|----------|---------|
| Shell Spawned in Container | CRITICAL | `kubectl exec` + shell |
| Unexpected Process in Payment | CRITICAL | ANY process in distroless payment-svc |
| Sensitive File Read | WARNING | `/etc/shadow`, SSH keys |
| Write in Immutable Container | ERROR | Write to readOnlyRootFilesystem |
| Package Manager Executed | ERROR | `apt`, `pip`, `npm` inside running container |
| Payment Unexpected Outbound | CRITICAL | payment-svc connecting to non-PG port |
| Privilege Escalation | CRITICAL | setuid binary executed |
| Container Drift | CRITICAL | Executable not in original image |
| /proc Recon | WARNING | Reading `/proc/1/environ` |
| Core Service Unexpected Port | WARNING | Outbound to non-approved ports |

**Test alert trigger**:
```bash
kubectl exec -it $(kubectl get pod -n tesco-core -l app=product-service \
  -o jsonpath='{.items[0].metadata.name}') -n tesco-core -- /bin/sh
# → Falco fires: CRITICAL: SHELL SPAWNED IN FRESHMART CONTAINER
```

---

### 4.8 — cert-manager + TLS Ingress

**What it does**: Automates TLS certificate lifecycle for HTTPS.

**Certificate chain**:
```
selfsigned-issuer (bootstrap CA creator)
        │
        ▼
freshmart-ca (root CA, 10yr, in cert-manager namespace)
        │
freshmart-ca-issuer (signs all app certs)
        │
        ├── freshmart-tls (tesco-frontend, 90 days, auto-renews)
        └── freshmart-api-tls (tesco-core, 90 days, auto-renews)
```

**Verified working output**:
```
HTTP/2 200
strict-transport-security: max-age=31536000; includeSubDomains
x-frame-options: DENY
x-content-type-options: nosniff
x-xss-protection: 1; mode=block
referrer-policy: strict-origin-when-cross-origin
permissions-policy: camera=(), microphone=(), geolocation=()
```

**In production (EKS)**: Replace `freshmart-ca-issuer` with `letsencrypt-prod` ACME issuer — free, browser-trusted certs, automatic renewal. Zero code changes.

---

### 4.9 — mTLS (Mutual TLS)

**What it does**: Cryptographically proves BOTH sides of the order→payment connection.

**Regular TLS vs mTLS**:
```
TLS:   Client verifies server identity only
mTLS:  BOTH verify each other — server rejects clients without a valid cert
```

**Two-layer protection for payment-service**:
```
NetworkPolicy  → Only order-service pod IP can reach port 8004 (L4, kernel)
mTLS           → Only client with CN=order-service cert can authenticate (L7, TLS)
```

An attacker who bypasses NetworkPolicy (e.g. via hostNetwork) still cannot authenticate — they have no valid client certificate.

**Go TLS config** (payment-service):
```go
ClientAuth: tls.RequireAndVerifyClientCert,
VerifyPeerCertificate: func(_, chains ...) error {
    cn := chains[0][0].Subject.CommonName
    if cn != "order-service" {
        return fmt.Errorf("unauthorized: CN=%s", cn)
    }
    return nil
},
```

**Python mTLS client** (order-service):
```python
async with httpx.AsyncClient(
    cert=(mtls_cert, mtls_key),   # present our client cert
    verify=mtls_ca                # verify payment-service's cert
) as client:
    resp = await client.post(url, json=payload)
```

---

### 4.10 — gVisor RuntimeClass

**What it does**: Runs payment-service inside a user-space kernel — all syscalls intercepted by gVisor, never reaching the host kernel directly.

```
Without gVisor:   container → syscall → host kernel (DIRECT)
With gVisor:      container → syscall → gVisor Sentry → limited syscalls → host kernel
```

**Applied to payment-service only** (highest-risk workload):
```yaml
spec:
  runtimeClassName: gvisor   # One line. That's it.
```

**Verification**:
```bash
# gVisor pods report kernel 4.4.0 (gVisor's fake kernel)
kubectl exec gvisor-pod -- uname -r
# 4.4.0

# Normal pods report real host kernel
kubectl exec normal-pod -- uname -r
# 5.15.x
```

**Defence in depth** on payment-service (all active simultaneously):
```
distroless image  → no shell, no OS tools
readOnlyRootFS    → immutable filesystem
NetworkPolicy     → kernel-level network isolation
mTLS              → TLS-layer identity verification
AppArmor          → file + network capability restrictions
seccomp           → syscall allowlist (35 of 400)
gVisor            → user-space kernel sandbox
```

---

### 4.11 — Vault + External Secrets Operator

**What it does**: Replaces plain K8s Secrets with Vault-managed, auto-rotating secrets.

**Three secrets migrated**:

| Phase 3 (plain K8s Secret) | Phase 4.11 (Vault-managed) |
|---------------------------|---------------------------|
| base64 in `02-secrets.yaml` | Encrypted in Vault KV-v2 |
| Static, never rotates | Can rotate via `vault kv patch` |
| No audit trail | Every read/write logged |
| Visible to anyone with `get secret` | Vault policy controls access |
| In Git (bad practice) | Never in Git |

**Rotation workflow**:
```bash
# 1. Update in Vault
vault kv patch secret/freshmart/database password="new-password"

# 2. Force ESO resync
kubectl annotate externalsecret db-credentials -n tesco-core \
  force-sync=$(date +%s) --overwrite

# 3. K8s Secret updates automatically
# 4. Restart pods to pick up new credentials
kubectl rollout restart deployment/order-service -n tesco-core
```

**Zero application changes** — pods still reference the same K8s Secret names as Phase 3. ESO handles the Vault → K8s Secret sync transparently.

---

## 11. Pending Phases 5–8

### Phase 5 — CI/CD Pipeline (GitHub Actions)

**Goal**: Every git push triggers security scanning, image building, signing, and registry push.

**Pipeline design**:

```yaml
# .github/workflows/ci.yaml

jobs:
  security-scan:
    steps:
      - Gitleaks          # Detect secrets in code/commits
      - Semgrep           # SAST: static code analysis
      - Safety/pip-audit  # Python dependency CVE scan
      - govulncheck       # Go dependency CVE scan

  build-and-scan:
    steps:
      - Docker build (multi-stage)
      - Trivy scan        # Container image CVE scan
      # FAIL on CRITICAL severity — blocks merge
      - trivy image --severity CRITICAL --exit-code 1

  sign-and-push:
    steps:
      - Cosign sign       # Sign image with Sigstore keyless signing
      # Produces: image:sha256-abc123.sig
      - Push to registry  # GitHub Container Registry or ECR
      - Syft SBOM         # Generate Software Bill of Materials

  update-gitops:
    steps:
      - Update Helm values.yaml with new image tag (Git SHA)
      - Commit to GitOps repo
      - ArgoCD detects change and syncs
```

**Image tagging strategy**:
```
# Never use :latest in production
freshmart/payment-service:v1.2.3          # Semantic version
freshmart/payment-service:main-abc1234    # Branch + Git SHA
freshmart/payment-service:sha256-abc...  # Digest (most immutable)
```

**OPA Gatekeeper integration**: The `K8sNoLatestTag` constraint is in `warn` mode now. Phase 5 adds versioned tags → switch to `deny`. Any deployment attempting `:latest` gets blocked at admission.

---

### Phase 6 — ArgoCD GitOps

**Goal**: Declarative, automated, auditable deployments via Git as the single source of truth.

**Repository structure**:
```
gitops-repo/
├── apps/
│   ├── freshmart/
│   │   ├── base/           # Kustomize base manifests
│   │   └── overlays/
│   │       ├── staging/    # Staging-specific patches
│   │       └── production/ # Production patches
│   └── infrastructure/     # Gatekeeper, cert-manager, Falco
└── argocd/
    └── applications/       # ArgoCD Application CRDs
```

**Deployment flow**:
```
Developer pushes code
         │
         ▼
GitHub Actions (Phase 5):
  - Security scans
  - Build + Trivy scan
  - Cosign sign
  - Push to registry
  - Update GitOps repo (values.yaml: image.tag = abc1234)
         │
         ▼
ArgoCD detects repo change (polling or webhook)
         │
         ▼
ArgoCD syncs to cluster:
  - OPA Gatekeeper validates (admission)
  - Kubernetes applies Deployment
  - Health checks pass
  - ArgoCD marks sync Healthy
         │
         ▼
Falco watches runtime:
  - Alerts on anomalous behaviour
  - Falco Sidekick → Slack/PagerDuty
```

**Key ArgoCD features**:
```bash
# Automated sync with self-heal
# If someone kubectl applies directly → ArgoCD reverts to Git state

# Progressive delivery (with Argo Rollouts)
# Blue/green or canary deployments for payment-service

# Rollback
argocd app rollback freshmart --revision 42
```

---

### Phase 7 — EKS (AWS Cloud Deployment)

**Goal**: Migrate from Kind to production EKS with AWS-native services.

**Terraform infrastructure**:
```
AWS Region: eu-west-1 (London — matching Tesco HQ)

VPC:
  ├── 3 public subnets  (ALB, NAT Gateway)
  └── 3 private subnets (EKS nodes, RDS, MSK)

EKS:
  ├── Control plane (AWS managed)
  └── Managed Node Groups:
      ├── general-purpose: t3.medium × 3 (app workloads)
      └── payment-critical: c5.large × 2 (payment + gVisor)

AWS Services (replaces local tools):
  PostgreSQL → AWS RDS Aurora Serverless v2
  Kafka      → AWS MSK (Managed Streaming for Kafka)
  Secrets    → AWS Secrets Manager + ESO
  TLS certs  → AWS ACM (Certificate Manager)
  Registry   → AWS ECR (Elastic Container Registry)
  Ingress    → AWS ALB + ALB Ingress Controller
  Falco      → Deployed on EC2 (full eBPF support)
```

**IRSA (IAM Roles for Service Accounts)**:
```yaml
# Each service gets an IAM Role via OIDC — no instance credentials
apiVersion: v1
kind: ServiceAccount
metadata:
  name: order-service-sa
  namespace: tesco-core
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/freshmart-order-role
```

**EKS CKS differences from Kind**:
```
Kind:  seccomp via hostPath mount on node
EKS:   seccomp via RuntimeDefault or custom profiles via Node Feature Discovery

Kind:  gVisor ptrace mode (slower)
EKS:   gVisor systrap mode on EC2 metal (faster)

Kind:  cert-manager self-signed CA
EKS:   cert-manager + Let's Encrypt OR AWS ACM for public certs

Kind:  Falco (limited by Docker Desktop)
EKS:   Falco full modern_ebpf on EC2 (kernel 5.10+)
```

---

### Phase 8 — Observability

**Goal**: Full visibility into cluster security, performance, and application health.

**Stack**:
```
Metrics:    Prometheus + Grafana
Logs:       Loki + Promtail
Traces:     Jaeger (distributed tracing)
Alerts:     Falco Sidekick → PagerDuty + Slack
Dashboards: Grafana (pre-built K8s + custom FreshMart dashboards)
```

**Security-specific dashboards**:
```
1. Falco Alerts Dashboard
   - Alert count by rule, namespace, severity
   - Timeline: alert spikes correlate with deployments
   - Top 5 most-triggered rules this week

2. Certificate Expiry Dashboard
   - All cert-manager certificates with days to expiry
   - Alert: cert expiring < 7 days → PagerDuty page

3. OPA Gatekeeper Violations
   - Violations by constraint name and namespace
   - Trend: are violations increasing after a code change?

4. RBAC Activity
   - K8s audit log: who accessed which Secrets
   - Alerts: unexpected `kubectl exec` in production namespace

5. Vault Audit Dashboard
   - Secret read/write frequency per path
   - Unusual access patterns (after-hours reads, bulk reads)
```

**Falco Sidekick routing**:
```yaml
# Alerts routed by severity:
CRITICAL → PagerDuty (immediate page, 5-min SLA)
ERROR    → Slack #security-alerts (30-min response)
WARNING  → Slack #security-review (next business day)
INFO     → Elasticsearch only (no immediate action)
```

---

## 12. DevSecOps — Zero to Hero Flow

### The Complete Pipeline (Phases 1–8 Combined)

```
 DEVELOPER                CI/CD PIPELINE              KUBERNETES             RUNTIME
     │                          │                          │                     │
     │  git push                │                          │                     │
     ├─────────────────────────►│                          │                     │
     │                          │  Gitleaks                │                     │
     │                          │  (secret scan)           │                     │
     │                          │                          │                     │
     │                          │  Semgrep SAST            │                     │
     │                          │  (code vulnerabilities)  │                     │
     │                          │                          │                     │
     │                          │  pip-audit / govulncheck │                     │
     │                          │  (dependency CVEs)       │                     │
     │                          │                          │                     │
     │                          │  docker build            │                     │
     │                          │  (multi-stage)           │                     │
     │                          │                          │                     │
     │                          │  Trivy scan              │                     │
     │                          │  CRITICAL? → FAIL BUILD  │                     │
     │                          │                          │                     │
     │                          │  Cosign sign             │                     │
     │                          │  + Syft SBOM             │                     │
     │                          │                          │                     │
     │                          │  Push to ECR             │                     │
     │                          │                          │                     │
     │                          │  Update GitOps repo      │                     │
     │                          │  (values.yaml: tag=SHA)  │                     │
     │                          │          │               │                     │
     │                          │   ArgoCD detects         │                     │
     │                          │   repo change            │                     │
     │                          │          │               │                     │
     │                          │          └──────────────►│                     │
     │                          │                          │  OPA Gatekeeper     │
     │                          │                          │  validates:         │
     │                          │                          │  - no :latest tag   │
     │                          │                          │  - allowed registry │
     │                          │                          │  - resource limits  │
     │                          │                          │  - non-root         │
     │                          │                          │                     │
     │                          │                          │  PSA: restricted    │
     │                          │                          │  (privileged → 403) │
     │                          │                          │                     │
     │                          │                          │  Pod starts         │
     │                          │                          │  AppArmor loaded    │
     │                          │                          │  seccomp loaded     │
     │                          │                          │  gVisor sandbox     │
     │                          │                          │                     │
     │                          │                          │          │          │
     │                          │                          │          └─────────►│
     │                          │                          │                     │ Falco
     │                          │                          │                     │ monitors
     │                          │                          │                     │ syscalls
     │                          │                          │                     │
     │                          │                          │                     │ ALERT:
     │                          │                          │                     │ shell in
     │◄─────────────────────────────────────────────────────────────────────────┤ container
     │  Slack: CRITICAL alert   │                          │                     │
```

### What "Shift-Left Security" Really Means

```
TRADITIONAL (shift-right):
  Code → Build → Test → Deploy → THEN check security
  Problem: Security issues found in production. Expensive to fix.

SHIFT-LEFT (our approach):
  Security at EVERY stage:

  Code stage:
    ✅ Gitleaks: secrets in commits blocked before push
    ✅ Semgrep: SQL injection, XSS caught in IDE/PR
    ✅ Pre-commit hooks: formatting + secret detection

  Build stage:
    ✅ pip-audit/govulncheck: known CVEs in dependencies
    ✅ Trivy: CVEs in the container image layers
    ✅ Cosign: image signing for provenance
    ✅ Syft SBOM: complete inventory of what's in the image

  Deploy stage:
    ✅ OPA Gatekeeper: policy enforcement at admission
    ✅ PSA: Pod Security Admission rejects unsafe configs
    ✅ ArgoCD: only Git-approved configs deployed

  Runtime stage:
    ✅ AppArmor: kernel capability restrictions
    ✅ seccomp: syscall filtering
    ✅ gVisor: kernel sandbox
    ✅ Falco: behavioural anomaly detection
    ✅ NetworkPolicy: zero-trust network

Cost of finding a vulnerability:
  Code:      $80
  Build:     $240
  Test:      $640
  Deploy:    $1,600
  Runtime:   $7,680  (source: IBM Cost of a Data Breach 2023)
```

### The Security Domains Explained Simply

```
┌────────────────────────────────────────────────────────────────────────┐
│  Think of it as a castle with multiple walls                            │
│                                                                          │
│  OUTER WALL (Network)                                                    │
│    NetworkPolicy    → who can talk to whom (no default routes)           │
│    Ingress TLS      → all external traffic encrypted                     │
│    mTLS             → internal services authenticated cryptographically  │
│                                                                          │
│  GATE (Admission)                                                        │
│    PSA              → standardised security policies enforced            │
│    OPA Gatekeeper   → custom business policies in Rego                   │
│                                                                          │
│  GUARD ROOMS (Runtime)                                                   │
│    AppArmor         → restricts what each process can access             │
│    seccomp          → restricts which kernel calls each process can make │
│    gVisor           → intercepts ALL syscalls at kernel level            │
│                                                                          │
│  SURVEILLANCE (Monitoring)                                               │
│    Falco            → watches for suspicious behaviour 24/7              │
│    K8s Audit Logs   → records every API action                           │
│    Vault Audit      → records every secret access                        │
│                                                                          │
│  VAULT (Secrets)                                                         │
│    Vault KV-v2      → single encrypted store for all credentials         │
│    ESO              → syncs to K8s Secrets automatically                 │
│    etcd encryption  → K8s Secrets encrypted on disk                     │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 13. CKS Domain Coverage

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CKS DOMAIN COVERAGE — ALL PHASES                          │
├──────────────────────────────────┬────────┬────────────────────────────────┤
│ Domain                           │ Weight │ Coverage                        │
├──────────────────────────────────┼────────┼────────────────────────────────┤
│ 1. Cluster Setup                 │  10%   │ ████████████ 100%              │
│ 2. Cluster Hardening             │  15%   │ ████████████ 95%               │
│ 3. System Hardening              │  15%   │ ████████████ 100%              │
│ 4. Microservice Vulnerabilities  │  20%   │ ████████████ 100%              │
│ 5. Supply Chain Security         │  20%   │ ████████░░░░ 70%               │
│ 6. Monitoring & Runtime Security │  20%   │ ████████░░░░ 70%               │
└──────────────────────────────────┴────────┴────────────────────────────────┘
  Supply Chain gaps: image signing (Cosign - Phase 5), SBOM (Syft - Phase 5)
  Runtime gaps: Falco deployment (Phase 7 - EKS)
```

### Domain 1: Cluster Setup (10%) — 100% ✅

| CKS Topic | Implemented | File |
|-----------|------------|------|
| NetworkPolicies — default deny | ✅ | `k8s/07-network-policies/` |
| NetworkPolicies — explicit allow | ✅ | `k8s/07-network-policies/` |
| Ingress with TLS | ✅ | `k8s/14-cert-manager/02-ingress-tls.yaml` |
| CIS Benchmark (kube-bench) | ✅ | `infra/kind/patch-control-plane.sh` |
| Protect node metadata | ✅ | NetworkPolicy blocks 169.254.169.254 |
| GUI/dashboard restriction | ✅ | No dashboard installed |

### Domain 2: Cluster Hardening (15%) — 95% ✅

| CKS Topic | Implemented | File |
|-----------|------------|------|
| RBAC — dedicated ServiceAccounts | ✅ | `k8s/01-rbac.yaml` |
| automountServiceAccountToken: false | ✅ | All ServiceAccounts |
| PSA (replaces PSP) | ✅ | `k8s/00-namespaces.yaml` |
| Restrict anonymous API access | ✅ | Phase 4.1 patch |
| etcd encryption at rest | ✅ | `k8s/09-etcd-encryption/` |
| K8s audit policy | ✅ | `k8s/08-audit-policy/` |
| Fine-grained RBAC roles | ✅ | `k8s/10-rbac-hardening/` |
| K8s version updates | ⏳ | Phase 7 (EKS upgrade process) |

### Domain 3: System Hardening (15%) — 100% ✅

| CKS Topic | Implemented | File |
|-----------|------------|------|
| seccompProfile: RuntimeDefault | ✅ | All Deployments (Phase 3) |
| Custom seccomp profiles | ✅ | `k8s/12-seccomp/` |
| runAsNonRoot + explicit UID | ✅ | All Deployments |
| allowPrivilegeEscalation: false | ✅ | All Deployments |
| capabilities: drop ALL | ✅ | All Deployments |
| readOnlyRootFilesystem | ✅ | payment-service |
| Minimal base images (distroless) | ✅ | All Dockerfiles |
| AppArmor custom profiles | ✅ | `k8s/11-apparmor/` |

### Domain 4: Microservice Vulnerabilities (20%) — 100% ✅

| CKS Topic | Implemented | File |
|-----------|------------|------|
| PSA restricted enforcement | ✅ | `k8s/00-namespaces.yaml` |
| Security contexts (pod + container) | ✅ | All Deployments |
| Resource requests + limits | ✅ | All Deployments |
| NetworkPolicy isolation | ✅ | `k8s/07-network-policies/` |
| OPA Gatekeeper (ConstraintTemplates) | ✅ | `k8s/13-opa-gatekeeper/` |
| Vault + External Secrets | ✅ | `k8s/17-vault-eso/` |
| mTLS (order→payment) | ✅ | `k8s/15-mtls/` |
| gVisor RuntimeClass | ✅ | `k8s/16-gvisor/` |
| Container sandboxing | ✅ | gVisor on payment-service |

### Domain 5: Supply Chain Security (20%) — 70% ✅

| CKS Topic | Implemented | File/Phase |
|-----------|------------|-----------|
| Minimal base images | ✅ | All Dockerfiles |
| Multi-stage builds | ✅ | All Dockerfiles |
| Non-root in Dockerfile | ✅ | All Dockerfiles |
| imagePullPolicy: Never (local) | ✅ | All Deployments |
| OPA: allowed registries | ✅ | `k8s/13-opa-gatekeeper/` |
| OPA: no latest tag | ✅ | `k8s/13-opa-gatekeeper/` |
| Trivy image scanning | ⏳ | Phase 5 (CI/CD) |
| Cosign image signing | ⏳ | Phase 5 (CI/CD) |
| SBOM generation (Syft) | ⏳ | Phase 5 (CI/CD) |

### Domain 6: Runtime Security (20%) — 70% ✅

| CKS Topic | Implemented | File/Phase |
|-----------|------------|-----------|
| seccomp reduces attack surface | ✅ | All Deployments + custom profiles |
| K8s audit logs | ✅ | `k8s/08-audit-policy/` |
| Immutable containers | ✅ | readOnlyRootFilesystem + Falco rules |
| Falco install + custom rules | ⏳ | Phase 7 (EKS) — rules written |
| Falco custom rules | ✅ | `security/falco/rules/freshmart-rules.yaml` |
| Behavioural anomaly detection | ⏳ | Phase 7 (EKS) |
| Log aggregation (Loki) | ⏳ | Phase 8 (Observability) |

---

## 14. AI in DevSecOps — Real-World Scenarios

### The AI Revolution in Security (2024–2026)

AI is fundamentally changing how security works in modern cloud-native platforms. Here's how the leading companies are integrating AI into their DevSecOps pipelines today.

### 1. AI-Powered Vulnerability Triage

**The problem**: Trivy finds 500 CVEs in a container image. Which 5 actually matter?

**Traditional approach**: Manual review — hours of work, context-free, often ignored.

**AI approach** (available today):
```
Tool: Anchore Enterprise + AI, Snyk AI, or custom LLM integration

Input to AI:
  - CVE: CVE-2024-XXXXX (CVSS 9.8)
  - Package: openssl 3.0.2
  - Your service: payment-service (Go binary, no web server, no TLS lib usage)
  - Traffic: internal-only, no external exposure

AI output:
  "CVE CRITICAL but UNEXPLOITABLE for payment-service.
   The vulnerability is in OpenSSL's DTLS handshake parser.
   payment-service uses gcr.io/distroless/static — no OpenSSL present.
   The Go binary links against Go's crypto/tls, not OpenSSL.
   Recommendation: FALSE POSITIVE — skip. Confidence: 97%"
```

This reduces alert fatigue by 80%+ (real-world metric from GitHub's security team).

**Integration in our pipeline**:
```yaml
# Phase 5 addition
- name: AI-powered CVE triage
  uses: snyk/actions/golang@master
  with:
    ai-triage: true
    suppress-false-positives: true
    context: payment-service-internal-only
```

---

### 2. AI Rego Policy Generation

**The problem**: Writing Rego policies is hard. Syntax is unfamiliar, logic is complex.

**AI approach**: Describe the policy in plain English → AI generates Rego.

**Example workflow**:
```
Prompt: "Write a Gatekeeper constraint that only allows images from our 
         internal registry (registry.freshmart.internal/) or 
         gcr.io/distroless/ in the tesco-payments namespace"

AI output:
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8spaymentallowedrepos
spec:
  crd:
    spec:
      names:
        kind: K8sPaymentAllowedRepos
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8spaymentallowedrepos
        
        allowed_prefixes := {
          "registry.freshmart.internal/",
          "gcr.io/distroless/"
        }
        
        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not image_allowed(container.image)
          msg := sprintf("Container '%v': image '%v' not from allowed registry",
            [container.name, container.image])
        }
        
        image_allowed(image) {
          prefix := allowed_prefixes[_]
          startswith(image, prefix)
        }
```

**Tools**:
- **Claude / ChatGPT**: generate Rego from plain English (what we're doing right now!)
- **Styra DAS**: AI-assisted policy management platform
- **OPA Playground**: test generated Rego interactively

---

### 3. AI-Enhanced Falco Rules

**The problem**: Writing Falco rules requires deep knowledge of syscalls and Linux internals.

**AI approach**: Describe the threat → AI generates the Falco rule.

**Example**:
```
Prompt: "Write a Falco rule to detect when a container in the tesco-payments 
         namespace makes an outbound DNS query to any domain other than 
         our internal cluster DNS (cluster.local)"

AI output:
- rule: FreshMart Payment External DNS Query
  desc: >
    payment-service made a DNS query outside cluster.local.
    payment-service has no business reason to query external DNS.
    This indicates data exfiltration via DNS tunnelling or C2 beaconing.
  condition: >
    evt.type = connect and
    container and
    k8s.ns.name = "tesco-payments" and
    fd.l4proto = UDP and
    fd.rport = 53 and
    not fd.rip startswith "10." and
    not fd.rip startswith "172.16."
  output: >
    PAYMENT: External DNS query detected (
    rip=%fd.rip domain=%dns.name pod=%k8s.pod.name)
  priority: CRITICAL
  tags: [payment, dns-exfiltration, T1048]
```

---

### 4. AI-Powered Anomaly Detection (Beyond Rules)

**The limitation of Falco rules**: Rules catch KNOWN bad patterns. Unknown attacks bypass rules.

**AI approach**: Learn what "normal" looks like, alert on statistical anomalies.

**Products**:
- **Sysdig Secure** (commercial): ML-based anomaly detection on top of Falco
- **Aqua Security** (commercial): AI drift detection
- **Deepfence ThreatMapper** (open source): graph-based threat detection
- **eBPF + ML**: Custom ML models on kernel telemetry (Netflix, Cloudflare approach)

**Example**:
```
ML baseline (30 days of data):
  payment-service:
  - Makes 150-200 DB connections/hour (normal)
  - CPU: 20-40ms per request (normal)
  - Memory: 45-55 MB (normal)
  - Outbound connections: ONLY to postgresql:5432 (normal)

Anomaly detected:
  - Sudden spike: 2,000 DB connections in 1 minute
  - CPU: 500ms per request
  - Memory: 200MB

AI decision:
  "Anomaly probability: 99.3% — possible SQL injection attack or 
   compromised connection pool. Correlates with: new deployment 3 
   minutes ago. Recommendation: rollback deployment abc1234 immediately."

Alert sent → PagerDuty → On-call engineer
```

---

### 5. AI in Kubernetes RBAC Audit

**The problem**: RBAC grows organically. After 2 years, no one knows who has access to what.

**AI approach**: Analyse all RBAC bindings, find privilege creep, suggest remediation.

**Tool**: `kubectl-who-can` + AI analysis, or `rback` (RBAC visualiser) + GPT-4 analysis.

**Workflow**:
```bash
# Export all RBAC
kubectl get rolebindings,clusterrolebindings -A -o json > rbac-audit.json

# Send to AI for analysis
# AI output:
"Found 3 over-privileged service accounts:
 1. order-service-sa has cluster-admin via clusterrolebinding (CRITICAL)
 2. product-service-sa has secrets:* on all namespaces (HIGH)
 3. frontend-sa has pods:create (MEDIUM — can create privileged pods)
 
 Remediation:
 1. Remove clusterrolebinding for order-service-sa
    kubectl delete clusterrolebinding order-service-cluster-admin
 2. Limit product-service-sa to secrets:get in tesco-core only
 3. Remove pods:create from frontend-sa"
```

---

### 6. AI-Generated Security Documentation

**Real use case**: Automated security reports for compliance (SOC2, ISO27001, PCI-DSS).

**Workflow**:
```bash
# AI gathers evidence automatically
kubectl get pods -A -o json
kubectl get networkpolicies -A -o json
kubectl get constrainttemplate -o json
vault audit list

# AI generates compliance report:
"PCI-DSS Requirement 1.3 (Prohibit direct public access to cardholder data):
  COMPLIANT — payment-service has no public Ingress route.
  NetworkPolicy ensures only order-service can reach payment-service.
  Evidence: k8s/07-network-policies/network-policies.yaml, line 89
  
 PCI-DSS Requirement 8.2 (Proper identification of users):
  COMPLIANT — All service accounts have automountServiceAccountToken: false.
  mTLS ensures cryptographic identity for inter-service communication.
  Evidence: k8s/15-mtls/00-certificates.yaml"
```

---

### 7. AI-Assisted Incident Response

**The problem**: During a security incident, engineers waste 40% of time on forensics.

**AI approach**: AI correlates logs, identifies root cause, suggests remediation — in seconds.

**Scenario**: Falco fires CRITICAL alert at 3am.

```
ALERT: Container Drift Detected in tesco-payments
       Executable not in original image was run

AI Incident Commander (auto-triggered):
  1. Querying Falco events for the past 1 hour... done
  2. Checking Vault audit for unusual secret access... done
  3. Reviewing K8s audit log for recent changes... done
  4. Correlating with deployment history... done

FINDINGS:
  22:47:03 — Deployment update: image tag changed to 'latest' (source: kubectl, user: bhargav@)
  22:47:45 — OPA Gatekeeper: warn (no-latest-tag constraint is in warn mode — DID NOT BLOCK)
  22:48:12 — Falco: Container drift: /tmp/reverse-shell executed in payment-service
  22:48:15 — Falco: Unexpected outbound: 192.168.1.100:4444 (potential reverse shell)
  22:48:18 — Vault: db-credentials read by: payment-service (unusual — not scheduled)

ROOT CAUSE: Compromised image deployed via 'latest' tag.
            Container ran /tmp/reverse-shell (planted in malicious image layer).
            Attacker exfiltrated DB credentials.

IMMEDIATE ACTIONS:
  1. kubectl delete pod payment-service-xxx -n tesco-payments  [AUTO-EXECUTED]
  2. vault kv put secret/freshmart/database password=<new>     [PENDING APPROVAL]
  3. Switch K8sNoLatestTag to enforcementAction: deny          [PENDING APPROVAL]

RUNBOOK: https://wiki.freshmart.internal/incidents/INCI-2024-0847
```

**Tools**: 
- AWS Security Hub + Bedrock (AWS-native)
- Microsoft Copilot for Security (Azure)
- Google Mandiant + Vertex AI
- Open source: Falco + LangChain + Claude API (what we could build)

---

### 8. AI for K8s Cost + Security Optimisation

**Goldilocks + AI**: Not too many permissions, not too few. Not too many resources, not too few.

```bash
# Goldilocks analyses pod resource usage vs limits
helm install goldilocks fairwinds-stable/goldilocks -n goldilocks
kubectl label namespace tesco-core goldilocks.fairwinds.com/enabled=true

# AI recommendation:
"payment-service currently has:
  requests: cpu=20m, memory=32Mi
  limits:   cpu=100m, memory=128Mi

Observed usage (p99 over 30 days):
  cpu: 8m average, 45m peak
  memory: 28Mi average, 68Mi peak

Recommendation:
  requests: cpu=10m, memory=30Mi
  limits:   cpu=60m, memory=80Mi
  
Cost saving: $47/month (t3.medium node share)
Security improvement: tighter limits reduce DoS blast radius"
```

---

## 15. Production Architecture (EKS)

### Target State (Phase 7)

```
                         INTERNET
                             │
                    ┌────────▼──────────┐
                    │  Cloudflare       │  DDoS protection
                    │  (edge CDN + TLS) │  WAF rules
                    └────────┬──────────┘
                             │
                    ┌────────▼──────────┐
                    │  AWS Route 53     │  DNS with health checks
                    └────────┬──────────┘
                             │
                    ┌────────▼──────────┐
                    │  AWS ALB           │  TLS via ACM (free, auto-renew)
                    │  (Application LB)  │  Target group: nginx ingress pods
                    └────────┬──────────┘
                             │
              ┌──────────────▼──────────────┐
              │  AWS EKS (eu-west-1)          │
              │                               │
              │  Private Subnets (3 AZs):     │
              │  ├── General Node Group       │
              │  │   (product, cart, order,   │
              │  │    frontend, kafka)         │
              │  └── Payment Node Group       │
              │      (payment-service only,   │
              │       gVisor, dedicated node) │
              └──────────────┬──────────────┘
                             │
              ┌──────────────▼──────────────────────────┐
              │  AWS Managed Services                      │
              │                                            │
              │  RDS Aurora Serverless v2  (PostgreSQL)   │
              │  MSK Serverless            (Kafka)         │
              │  Secrets Manager           (DB creds)      │
              │  ECR                       (images)        │
              │  S3                        (SBOM, backups) │
              │  CloudWatch                (audit logs)    │
              └──────────────────────────────────────────┘
```

### Migration Checklist (Kind → EKS)

```bash
# 1. Terraform apply (VPC, EKS, RDS, MSK)
cd terraform/
terraform init && terraform plan && terraform apply

# 2. Update kubeconfig
aws eks update-kubeconfig --name freshmart-prod --region eu-west-1

# 3. Install cluster-level tools via Helm
helm install cert-manager jetstack/cert-manager ...       # replace self-signed with ACME
helm install aws-load-balancer-controller ...              # replace nginx ingress
helm install external-secrets external-secrets/external-secrets ...
helm install falco falcosecurity/falco --set driver.kind=modern_ebpf  # works on EC2!

# 4. Update image references
# All manifests: freshmart/ → 123456789.dkr.ecr.eu-west-1.amazonaws.com/freshmart/

# 5. Replace cert-manager self-signed with Let's Encrypt
kubectl apply -f k8s/letsencrypt-issuer.yaml  # switch ClusterIssuer

# 6. Update ESO to use AWS Secrets Manager
# Replace vault ClusterSecretStore with awsSecretsManager provider

# 7. IRSA for service accounts
kubectl annotate sa order-service-sa -n tesco-core \
  eks.amazonaws.com/role-arn=arn:aws:iam::123:role/freshmart-order

# 8. Verify
kubectl get pods -A
curl https://freshmart.io/api/products
```

---

## 16. Manual Testing Guide

### Full Checkout Test

```bash
# 1. Add item to cart
curl -sk -X POST https://freshmart.local/api/cart/test-123/items \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "quantity": 2}' | python3 -m json.tool

# 2. View cart
curl -sk https://freshmart.local/api/cart/test-123 | python3 -m json.tool

# 3. Place order (triggers mTLS call to payment-service)
curl -sk -X POST https://freshmart.local/api/orders \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "test-123",
    "delivery_address": {
      "full_name": "Test User",
      "address_line1": "1 K8s Street",
      "city": "London",
      "postcode": "SW1A 1AA"
    },
    "payment_details": {
      "card_number": "4242424242424242",
      "expiry": "12/27",
      "cvv": "123"
    }
  }' | python3 -m json.tool
```

### Security Tests

```bash
# Test OPA Gatekeeper blocks wrong registry
kubectl run blocked --image=nginx:1.25 -n tesco-core --restart=Never
# → Error: freshmart-allowed-repos denied the request

# Test OPA blocks privileged pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: {name: test-priv, namespace: tesco-core}
spec:
  containers:
  - name: t
    image: freshmart/product-service:latest
    securityContext: {privileged: true}
    resources: {limits: {cpu: "50m", memory: "64Mi"}}
  securityContext: {runAsNonRoot: true, seccompProfile: {type: RuntimeDefault}}
EOF
# → Error: freshmart-no-privileged denied the request

# Test mTLS works
kubectl exec -n tesco-core deploy/order-service -- \
  openssl s_client \
    -connect payment-service.tesco-payments.svc.cluster.local:8004 \
    -cert /certs/tls.crt -key /certs/tls.key -CAfile /certs/ca.crt \
    -brief 2>&1 | grep -E "CONNECTION|Protocol|Verify"

# Test gVisor isolation
kubectl run gv-test --image=busybox:1.36 \
  --overrides='{"spec":{"runtimeClassName":"gvisor"}}' \
  --restart=Never -- sh -c "uname -r"
kubectl logs gv-test
# → 4.4.0 (gVisor fake kernel, not host 5.x)

# Verify etcd encryption
docker exec freshmart-cks-control-plane sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/tesco-core/db-credentials | strings | head -3
'
# → k8s:enc:aescbc:v1:freshmart-key-1:... (encrypted, not plaintext)
```

---

## 17. CKS Exam Preparation

### High-Frequency Exam Topics (from this project)

```
1. NetworkPolicy — "create a default deny policy" then "allow X to reach Y"
2. RBAC — "create a role that can only read secrets in namespace X"
3. etcd encryption — "encrypt secrets at rest using aescbc"
4. Audit policy — "log all access to secrets"
5. PodSecurityAdmission — "restrict namespace to restricted profile"
6. Falco — "create a rule to detect shell execution"
7. AppArmor — "enforce an AppArmor profile on a container"
8. seccomp — "configure a container to use RuntimeDefault seccomp"
9. ImagePolicyWebhook / OPA — "block images from non-approved registries"
10. gVisor RuntimeClass — "create RuntimeClass and apply to a pod"
11. Service Account tokens — "disable automounting of service account token"
12. TLS — "configure TLS on the ingress"
```

### Exam Environment Tips

```bash
# The exam is time-pressured. Use aliases:
alias k=kubectl
alias kn='kubectl -n'
export do="--dry-run=client -o yaml"

# Common kubectl shortcuts
k get pods -A                      # all namespaces
k get pods --field-selector=status.phase!=Running
k describe pod <pod> | grep -A5 Events
k auth can-i list secrets -n tesco-core --as=system:serviceaccount:tesco-core:order-service-sa

# Apply from stdin (fast for exam)
cat <<EOF | k apply -f -
...yaml...
EOF

# Edit in-place
k edit pod <name>
k patch deployment <name> --type=json -p='[...]'
```

### Most Common Mistakes in CKS Exam

```
1. etcd encryption: forgetting to re-encrypt existing secrets
   Fix: kubectl get secrets --all-namespaces -o json | kubectl replace -f -

2. NetworkPolicy: spec.podSelector: {} doesn't mean "select nothing"
   It means "select all pods in this namespace"
   Use matchLabels: {no-such-label: "true"} to select nothing

3. RBAC: Role vs ClusterRole
   Role = namespaced (applies in one namespace)
   ClusterRole = cluster-wide (applies everywhere)

4. PSA labels: three separate labels needed
   pod-security.kubernetes.io/enforce: restricted
   pod-security.kubernetes.io/audit: restricted
   pod-security.kubernetes.io/warn: restricted

5. Audit policy: "Metadata" level logs the request but NOT the response body
   For secrets, always use Metadata (not Request/Response — logs the secret value!)
```

---

## 18. Interview Preparation

### Senior DevSecOps Engineer Questions (with Answers from This Project)

**Q: "Walk me through how you'd secure a payment service in Kubernetes."**

```
A: I'd apply a layered approach:

1. Network isolation (NetworkPolicy: default-deny-all, only order-service allowed)
2. No public ingress route (payment is internal-only — no Ingress resource)
3. Minimal image (Go binary in distroless/static — no shell, no OS)
4. Read-only root filesystem (readOnlyRootFilesystem: true)
5. Non-root (uid 65532, PSA: restricted enforced)
6. mTLS: require client certificate from order-service, verify CN
7. AppArmor: custom profile blocking unnecessary file/network operations
8. seccomp: custom profile allowing only ~35 syscalls the Go binary needs
9. gVisor: user-space kernel sandbox — all syscalls intercepted
10. Vault: dynamic DB credentials via ESO (no static passwords)
11. Falco: rules for any process execution, unexpected outbound, shell spawns

All of these are in my FreshMart project — I can show you the code.
```

**Q: "How do OPA Gatekeeper and Pod Security Admission differ?"**

```
A: Both are admission controllers but serve different purposes:

PSA: Built into Kubernetes. Three fixed profiles (privileged/baseline/restricted).
     Applied via namespace labels. Very fast, zero configuration.
     Good for: baseline security hygiene across all namespaces.

OPA Gatekeeper: External webhook. Fully custom policies in Rego.
                Parameterised (e.g., allowed registries list is configurable).
                Three enforcement modes: deny/warn/dryrun for gradual rollout.
                Good for: business-specific policies (allowed registry list,
                          required labels, team-specific rules).

In production: use both. PSA as the first gate (free, always on),
Gatekeeper for custom business policies on top.
```

**Q: "Explain mTLS vs regular TLS."**

```
A: Regular TLS: the client verifies the server's certificate only.
   The server doesn't know WHO the client is — anyone can connect.

   mTLS: both sides present certificates. The server requires a valid
   client cert signed by a trusted CA. The server can verify not just
   "is this a valid cert" but also "is this cert's CN=order-service?"
   
   In payment-service, I enforce:
   - RequireAndVerifyClientCert: no cert = handshake rejected at TLS layer
   - VerifyPeerCertificate: check CN="order-service" — even a valid cert 
     from another service gets rejected
   
   Combined with NetworkPolicy, this gives two independent isolation layers.
   An attacker needs to bypass BOTH the kernel network rules AND forge a 
   certificate signed by our internal CA.
```

**Q: "How does gVisor protect against container escapes?"**

```
A: In a standard container (runc), if an attacker exploits a CVE in the
   application, they can call any Linux syscall directly — including ones
   that lead to container escapes like ptrace, mount, unshare, or pivot_root.

   With gVisor, all syscalls go to gVisor's user-space kernel (Sentry),
   not the real host kernel. The attack surface is reduced to:
   1. The application code (still exploitable)
   2. The gVisor Sentry (much smaller codebase, memory-safe Go)
   3. A very limited number of syscalls gVisor makes to the host

   Even if you exploit the application and the gVisor Sentry, you still
   need to exploit the limited host kernel interface gVisor uses.
   That's three layers instead of one.
```

---

## 19. Resources & References

### Official Documentation

| Resource | URL | Relevance |
|----------|-----|-----------|
| CKS Curriculum | [kubernetes.io/certifications/cks](https://kubernetes.io/certifications/cks) | Exam topics |
| Kubernetes Security | [kubernetes.io/docs/concepts/security](https://kubernetes.io/docs/concepts/security) | PSA, RBAC, NetworkPolicy |
| CIS Kubernetes Benchmark | [cisecurity.org](https://www.cisecurity.org/benchmark/kubernetes) | kube-bench basis |
| OPA Gatekeeper | [open-policy-agent.github.io/gatekeeper](https://open-policy-agent.github.io/gatekeeper) | Policy-as-code |
| Falco | [falco.org](https://falco.org) | Runtime security |
| cert-manager | [cert-manager.io](https://cert-manager.io) | TLS lifecycle |
| HashiCorp Vault | [vaultproject.io](https://www.vaultproject.io) | Secrets management |
| External Secrets | [external-secrets.io](https://external-secrets.io) | ESO docs |
| gVisor | [gvisor.dev](https://gvisor.dev) | Container sandbox |

### Phase Documentation (in this repo)

| File | Content |
|------|---------|
| `PHASE-3-CKS-KUBERNETES.md` | Kind cluster, namespaces, RBAC, NetworkPolicy |
| `PHASE-4.1-KUBE-BENCH.md` | CIS benchmark, fixes, exam commands |
| `PHASE-4.2-ETCD-ENCRYPTION.md` | AES-256 encryption, verification, key rotation |
| `PHASE-4.3-RBAC.md` | Fine-grained RBAC, least privilege patterns |
| `PHASE-4.4-APPARMOR.md` | Profile writing, loading, verification |
| `PHASE-4.5-SECCOMP.md` | JSON profiles, syscall filtering, strace |
| `PHASE-4.6-OPA-GATEKEEPER.md` | Rego, ConstraintTemplates, test scenarios |
| `PHASE-4.7-FALCO.md` | Custom rules, anatomy, real-world alerts |
| `PHASE-4.8-CERT-MANAGER-TLS.md` | CA chain, HTTPS verification, Vault comparison |
| `PHASE-4.9-MTLS.md` | Certificate design, Go/Python code, handshake test |
| `PHASE-4.10-GVISOR.md` | Architecture, platforms, verification, production |
| `PHASE-4.11-VAULT-ESO.md` | Vault config, ESO flow, rotation, audit |

### Tools To Know for Job Interviews

```
Container Security:   Trivy, Grype, Snyk, Aqua, Prisma Cloud
Runtime Security:     Falco, Sysdig, Aqua Runtime
Policy:               OPA/Gatekeeper, Kyverno, Styra DAS
Secrets:              Vault, AWS Secrets Manager, Azure Key Vault
Service Mesh:         Istio, Linkerd, Cilium
Image Signing:        Cosign, Notary v2
SBOM:                 Syft, CycloneDX
SAST:                 Semgrep, SonarQube, Checkmarx
Secret Scanning:      Gitleaks, TruffleHog, GitGuardian
K8s Security:         kube-bench, kube-hunter, Kubescape
Chaos Engineering:    Chaos Monkey, LitmusChaos (security resilience testing)
```

---

## Contributing

This project is built as a learning reference. Each phase is documented with:
- What was built and why
- CKS exam relevance
- Real-world context
- Manual testing guide

If you find a bug or better approach, the pattern is established — open a PR with a corresponding `PHASE-X.Y-UPDATE.md` explaining the change.

---

## License

MIT — use freely for learning, interviews, and as a template for real projects.

---

*Built by Bhargav | CKS DevSecOps Portfolio Project*

*Last updated: June 2026 | Kubernetes v1.35 | cert-manager v1.16 | Falco 0.39 | Vault Latest*
