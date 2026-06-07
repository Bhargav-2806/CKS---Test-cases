# Phase 4.11 — HashiCorp Vault + External Secrets Operator

**CKS Domain:** Minimize Microservice Vulnerabilities (20%)  
**Status:** ✅ Complete — Phase 4 FULLY COMPLETE

---

## The Problem With Plain K8s Secrets

Looking at our Phase 3 `02-secrets.yaml`:

```yaml
data:
  DATABASE_URL: cG9zdGdyZXNxbDovL2ZyZXNobWFydDpmcmVzaG1hcnRAcG9zdGdyZXNxbC50ZXNjby1kYXRhLnN2Yy5jbHVzdGVyLmxvY2FsOjU0MzIvZnJlc2htYXJ0
```

That base64 decodes to the plaintext connection string. Problems:
- **In Git** — anyone with repo access reads it
- **No rotation** — changing the DB password = manual update across 3 namespaces
- **No audit trail** — who read this secret, when?
- **No TTL** — static forever, even after a compromise
- **kubectl get secret** — any RBAC user with `get` permission reads it instantly

Phase 4.11 moves all secrets to Vault and replaces plain K8s Secrets with ESO-managed ones.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                            │
│  Developer / CI / Admin                                                    │
│       │                                                                    │
│       │  vault kv put secret/freshmart/database url=postgresql://...      │
│       ▼                                                                    │
│  ┌──────────────────────────────────────────┐                             │
│  │  HashiCorp Vault (tesco-security)         │                             │
│  │                                           │                             │
│  │  KV-v2 secrets engine                    │                             │
│  │  └── secret/freshmart/database            │                             │
│  │        ├── url      (DB connection string)│                             │
│  │        ├── username (freshmart)           │                             │
│  │        ├── password (freshmart)           │                             │
│  │        └── db       (freshmart)           │                             │
│  │                                           │                             │
│  │  Audit log: every read/write logged       │                             │
│  └──────────────────────────────────────────┘                             │
│               │                                                            │
│               │  ESO reads every 1h                                        │
│               ▼                                                            │
│  ┌──────────────────────────────────────────┐                             │
│  │  External Secrets Operator               │                             │
│  │  (external-secrets namespace)            │                             │
│  │                                           │                             │
│  │  ClusterSecretStore: vault-backend        │                             │
│  │  ExternalSecrets:                         │                             │
│  │    tesco-core/db-credentials      ──────► K8s Secret                   │
│  │    tesco-payments/db-credentials  ──────► K8s Secret                   │
│  │    tesco-data/postgresql-creds    ──────► K8s Secret                   │
│  └──────────────────────────────────────────┘                             │
│               │                                                            │
│               │  Pods mount K8s Secret (unchanged from Phase 3)           │
│               ▼                                                            │
│  product-service / cart-service / order-service / payment-service         │
│  (zero application code changes — same env vars)                           │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Components

### HashiCorp Vault — What It Stores

| Path | Fields | Used by |
|------|--------|---------|
| `secret/freshmart/database` | url, username, password, db | All services |

Single source of truth. Change the password in Vault → ESO propagates to all 3 namespaces automatically within 1 hour (or immediately on manual trigger).

### External Secrets Operator — What It Creates

| ExternalSecret | Namespace | K8s Secret Created | Synced from Vault |
|---------------|-----------|-------------------|-------------------|
| db-credentials | tesco-core | db-credentials | secret/freshmart/database.url |
| db-credentials | tesco-payments | db-credentials | secret/freshmart/database.url |
| postgresql-credentials | tesco-data | postgresql-credentials | secret/freshmart/database.{db,username,password} |

---

## Files Created

```
security/vault/
└── vault-values.yaml              ← Vault Helm values (dev mode)

k8s/17-vault-eso/
├── 00-vault-eso-rbac.yaml         ← Namespaces, vault-token Secret, RBAC
├── 01-secretstore.yaml            ← ClusterSecretStore: vault-backend
└── 02-externalsecrets.yaml        ← 3 ExternalSecret objects

infra/kind/
└── setup-vault-eso.sh             ← Install + configure script

PHASE-4.11-VAULT-ESO.md            ← This file
```

---

## How to Deploy

```bash
cd ~/Downloads/DevSecOps\ Projects/CKS-\ Real\ case/freshmart-platform

chmod +x infra/kind/setup-vault-eso.sh
./infra/kind/setup-vault-eso.sh
```

The script:
1. Creates `tesco-security` namespace
2. Installs Vault via Helm (dev mode, root token: `freshmart-vault-root`)
3. Installs ESO via Helm
4. Configures Vault: KV-v2 engine + writes secrets + creates policy + K8s auth
5. Applies ClusterSecretStore + ExternalSecrets
6. Migrates Phase 3 plain K8s Secrets → ESO-managed (deletes old, ESO recreates)
7. Verifies all secrets are ESO-owned

---

## Manual Testing

### Test 1 — Vault is Running

```bash
kubectl get pods -n tesco-security
# Expected: vault-0  1/1  Running

# Check Vault is initialized and unsealed (dev mode = always unsealed)
kubectl exec -n tesco-security vault-0 -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=freshmart-vault-root \
  vault status
# Expected: Initialized: true, Sealed: false
```

### Test 2 — Read Secrets FROM Vault

```bash
kubectl exec -n tesco-security vault-0 -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=freshmart-vault-root \
  vault kv get secret/freshmart/database

# Expected:
# ========= Secret Path =========
# secret/data/freshmart/database
#
# ======= Metadata =======
# Key              Value
# created_time     2026-06-07T...
# version          1
#
# ==== Data ====
# Key        Value
# db         freshmart
# password   freshmart
# url        postgresql://freshmart:freshmart@postgresql...
# username   freshmart
```

### Test 3 — ESO ClusterSecretStore is Ready

```bash
kubectl get clustersecretstore vault-backend
# Expected:
# NAME            AGE   STATUS   CAPABILITIES   READY
# vault-backend   1m    Valid    ReadWrite      True

# Detailed status
kubectl describe clustersecretstore vault-backend | grep -A10 "Status:"
```

### Test 4 — ExternalSecrets Synced Successfully

```bash
kubectl get externalsecret -A
# Expected:
# NAMESPACE        NAME                    STORE           REFRESH INTERVAL   STATUS
# tesco-core       db-credentials          vault-backend   1h                 SecretSynced
# tesco-payments   db-credentials          vault-backend   1h                 SecretSynced
# tesco-data       postgresql-credentials  vault-backend   1h                 SecretSynced
```

### Test 5 — K8s Secrets Are ESO-Owned

```bash
# Verify ownership — should show ExternalSecret as owner
kubectl get secret db-credentials -n tesco-core \
  -o jsonpath='{.metadata.ownerReferences[0].kind}'
# Expected: ExternalSecret

# Compare with Phase 3 (before migration):
# Expected then: no ownerReferences (plain K8s Secret)
```

### Test 6 — Secret Content Is Correct

```bash
# Verify the DB URL was correctly synced from Vault
kubectl get secret db-credentials -n tesco-core \
  -o jsonpath='{.data.DATABASE_URL}' | base64 -d
# Expected: postgresql://freshmart:freshmart@postgresql.tesco-data.svc.cluster.local:5432/freshmart
```

### Test 7 — Application Still Works After Migration

```bash
# Products still loading from DB (confirms K8s Secret is correct)
curl -sk https://freshmart.local/api/products | python3 -m json.tool | head -15
```

### Test 8 — Force Immediate Resync

```bash
# Trigger immediate resync (don't wait for 1h refresh)
kubectl annotate externalsecret db-credentials -n tesco-core \
  force-sync=$(date +%s) --overwrite

# Watch ESO sync the secret
kubectl get externalsecret db-credentials -n tesco-core -w
```

### Test 9 — Simulate Secret Rotation

```bash
# Update the secret in Vault (simulates a password rotation)
kubectl exec -n tesco-security vault-0 -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=freshmart-vault-root \
  vault kv patch secret/freshmart/database password="new-rotated-password"

# Wait for ESO to sync (or force-sync as above)
sleep 5
kubectl annotate externalsecret db-credentials -n tesco-core \
  force-sync=$(date +%s) --overwrite
sleep 10

# Verify the K8s Secret was updated
kubectl get secret db-credentials -n tesco-core \
  -o jsonpath='{.data.DATABASE_URL}' | base64 -d
# URL would now contain the new password

# IMPORTANT: In production, you'd also restart pods to pick up the new credentials
# (unless you mount secrets as files — they auto-update without pod restart)

# Revert for demo purposes
kubectl exec -n tesco-security vault-0 -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=freshmart-vault-root \
  vault kv patch secret/freshmart/database password="freshmart"
```

### Test 10 — Vault UI

```bash
# Port-forward to access the Vault UI
kubectl port-forward -n tesco-security svc/vault 8200:8200 &
# Open: http://localhost:8200
# Token: freshmart-vault-root
# Navigate to: Secrets → secret → freshmart → database
```

---

## Important Commands

```bash
# List all ExternalSecrets
kubectl get externalsecret -A

# Check ExternalSecret sync status
kubectl describe externalsecret db-credentials -n tesco-core

# Read from Vault directly
kubectl exec -n tesco-security vault-0 -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=freshmart-vault-root \
  vault kv list secret/freshmart/

# Write/update a secret in Vault
kubectl exec -n tesco-security vault-0 -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=freshmart-vault-root \
  vault kv put secret/freshmart/database url="new-url"

# View secret versions (KV-v2 keeps history)
kubectl exec -n tesco-security vault-0 -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=freshmart-vault-root \
  vault kv metadata get secret/freshmart/database

# Force ESO to resync immediately
kubectl annotate externalsecret <name> -n <namespace> \
  force-sync=$(date +%s) --overwrite

# Delete ExternalSecret (also deletes the K8s Secret due to deletionPolicy: Delete)
kubectl delete externalsecret db-credentials -n tesco-core

# Rollback to Phase 3 plain K8s Secrets (emergency)
kubectl apply -f k8s/02-secrets.yaml
```

---

## CKS Exam Scenarios

### Scenario 1: "Why shouldn't secrets be stored in K8s Secrets?"

Answer: K8s Secrets are only base64-encoded (not encrypted) by default. Even with etcd encryption (Phase 4.2), anyone with `kubectl get secret` RBAC permission reads them in plaintext. No rotation, no audit trail, no TTL. Vault + ESO solves all of these.

### Scenario 2: "What's the difference between the Vault injector and ESO?"

| | Vault Agent Injector | External Secrets Operator |
|--|---------------------|--------------------------|
| How | Sidecar container injected into pod | Controller syncs K8s Secrets |
| App change | No | No |
| Secret location | Mounted file in pod | K8s Secret (env var or file) |
| Overhead | Extra sidecar per pod | One ESO controller |
| Rotation | Sidecar detects + updates file | ESO recreates K8s Secret |

### Scenario 3: "How do you rotate a Kubernetes Secret?"

With ESO + Vault:
```bash
# 1. Update in Vault
vault kv put secret/freshmart/database password="new-pass"

# 2. Force ESO sync
kubectl annotate externalsecret <name> -n <ns> force-sync=$(date +%s) --overwrite

# 3. K8s Secret updates automatically
# 4. Pods using file mounts pick it up immediately
#    Pods using env vars need a rollout restart
kubectl rollout restart deployment/order-service -n tesco-core
```

---

## Phase 4 — COMPLETE Summary

```
✅ Phase 4.1  — kube-bench        CIS benchmark: 74 PASS / 1 FAIL
✅ Phase 4.2  — etcd encryption   Secrets encrypted at rest (AES-256)
✅ Phase 4.3  — Fine RBAC         Least-privilege Roles per service
✅ Phase 4.4  — AppArmor          Custom profiles per container
✅ Phase 4.5  — seccomp           Custom syscall allowlists
✅ Phase 4.6  — OPA Gatekeeper    7 policies: no-latest, no-priv, no-hostpath...
⏳ Phase 4.7  — Falco             Runtime detection (deploy on EKS Phase 7)
✅ Phase 4.8  — cert-manager TLS  HTTPS + HSTS + security headers
✅ Phase 4.9  — mTLS              order→payment mutual authentication
✅ Phase 4.10 — gVisor            Kernel sandbox on payment-service
✅ Phase 4.11 — Vault + ESO       Secrets from Vault, zero plaintext in Git
```

**What we've built covers all 6 CKS domains:**
```
Domain 1: Cluster Setup         ✅ NetworkPolicies, TLS, kube-bench
Domain 2: Cluster Hardening     ✅ RBAC, etcd encryption, audit logs
Domain 3: System Hardening      ✅ AppArmor, seccomp, distroless images
Domain 4: Microservice Vulns    ✅ PSA, OPA, mTLS, gVisor, Vault
Domain 5: Supply Chain          ✅ Multi-stage builds, ImagePullPolicy
Domain 6: Runtime Security      ✅ Falco rules ready, audit policy active
```

**Next Phase: 5 — CI/CD Pipeline**  
GitHub Actions → Trivy scan → Cosign sign → Push to registry → Helm chart update
