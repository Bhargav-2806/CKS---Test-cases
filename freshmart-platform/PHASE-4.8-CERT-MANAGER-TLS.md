# Phase 4.8 — cert-manager + TLS Ingress

**CKS Domain:** Cluster Setup (10%) — Ingress with TLS  
**Status:** ✅ Complete

---

## What Is cert-manager?

cert-manager is a Kubernetes-native **certificate lifecycle manager**. It automates:
- Issuing TLS certificates (self-signed, Let's Encrypt, Vault, or your own CA)
- Storing them as Kubernetes Secrets
- **Automatically renewing** them before expiry

Without cert-manager, you'd manually generate certs, copy them into Secrets, and remember to rotate them every 90 days. With cert-manager, you declare what you want and it handles the rest forever.

```
You declare:                cert-manager does:
─────────────────           ──────────────────────────────────────
Certificate object    →     1. Generate private key
(namespace, dnsNames,       2. Create CSR
 issuerRef, duration)       3. Send to issuer (CA/ACME/Vault)
                            4. Store signed cert in Secret
                            5. Watch expiry
                            6. Re-issue 15 days before expiry
                            7. Repeat forever
```

---

## Certificate Chain — How We Set It Up

We use a **two-level CA chain** (best practice):

```
selfsigned-issuer (ClusterIssuer)
        │
        │ issues
        ▼
freshmart-ca (Certificate — isCA: true)
        │ stored in freshmart-ca-secret
        │
freshmart-ca-issuer (ClusterIssuer)
        │
        │ issues
        ├─── freshmart-tls (tesco-frontend)     → used by frontend Ingress
        └─── freshmart-api-tls (tesco-core)     → used by API Ingress
```

**Why two levels?**
A plain `selfSigned` issuer creates a cert that is its own CA — untrusted to everything. A CA issuer signs all certs from one root. Trust the CA once → all certs it signs are trusted. This is how real corporate PKI works: install the company CA, trust all internal services automatically.

---

## Files Created

```
k8s/14-cert-manager/
├── 00-clusterissuers.yaml      ← selfsigned bootstrapper + CA cert + CA issuer
├── 01-certificates.yaml        ← TLS certs for tesco-frontend + tesco-core
└── 02-ingress-tls.yaml         ← Updated Ingresses (host + TLS + headers)

infra/kind/
└── setup-cert-manager.sh       ← install + configure script

PHASE-4.8-CERT-MANAGER-TLS.md  ← this file
```

---

## What Changed in the Ingresses

### Before (Phase 3)
```yaml
spec:
  ingressClassName: nginx
  rules:
    - http:              # ← no host — matches any hostname
        paths:
          - path: /
```

### After (Phase 4.8)
```yaml
spec:
  ingressClassName: nginx
  tls:                          # ← TLS termination added
    - hosts:
        - freshmart.local
      secretName: freshmart-tls # ← cert-manager puts cert here
  rules:
    - host: freshmart.local     # ← host-based routing
      http:
        paths:
          - path: /
```

Plus new annotations:
```yaml
nginx.ingress.kubernetes.io/ssl-redirect: "true"        # HTTP → HTTPS
nginx.ingress.kubernetes.io/force-ssl-redirect: "true"  # even behind proxy
nginx.ingress.kubernetes.io/hsts: "true"                # HSTS header
nginx.ingress.kubernetes.io/hsts-max-age: "31536000"    # 1 year
```

And security response headers:
```
X-Frame-Options: DENY                    ← blocks clickjacking
X-Content-Type-Options: nosniff          ← blocks MIME sniffing
X-XSS-Protection: 1; mode=block         ← XSS filter
Referrer-Policy: strict-origin-...      ← limits referrer leakage
Content-Security-Policy: ...            ← (frontend only) limits asset sources
```

---

## How to Deploy

```bash
cd ~/Downloads/DevSecOps\ Projects/CKS-\ Real\ case/freshmart-platform

chmod +x infra/kind/setup-cert-manager.sh
./infra/kind/setup-cert-manager.sh
```

Then add `freshmart.local` to your Mac's `/etc/hosts`:
```bash
sudo sh -c 'echo "127.0.0.1 freshmart.local" >> /etc/hosts'
```

---

## Manual Testing

### Test 1 — Certificate is Ready

```bash
# Check all certificates are Ready
kubectl get certificate -A

# Expected:
# NAMESPACE        NAME               READY   SECRET              AGE
# cert-manager     freshmart-ca       True    freshmart-ca-secret  2m
# tesco-core       freshmart-api-tls  True    freshmart-api-tls   1m
# tesco-frontend   freshmart-tls      True    freshmart-tls       1m
```

### Test 2 — TLS Secret Exists

```bash
# The Secret contains: tls.crt + tls.key
kubectl get secret freshmart-tls -n tesco-frontend

# Inspect the certificate details
kubectl get secret freshmart-tls -n tesco-frontend \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | \
  grep -E "Subject:|Issuer:|Not After|DNS:"

# Expected:
# Subject: O=FreshMart, CN=freshmart.local
# Issuer:  CN=freshmart-local-ca
# Not After: <90 days from now>
# DNS: freshmart.local
```

### Test 3 — HTTPS Works

```bash
# -k ignores self-signed cert warning (expected for local CA)
curl -k https://freshmart.local/api/products | python3 -m json.tool | head -20
curl -k https://freshmart.local/api/cart/test-session
curl -k -I https://freshmart.local

# Check response headers include security headers
curl -k -I https://freshmart.local 2>/dev/null | grep -E \
  "X-Frame|X-Content|X-XSS|Strict-Transport|Content-Security"

# Expected headers:
# X-Frame-Options: DENY
# X-Content-Type-Options: nosniff
# Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```

### Test 4 — HTTP Redirects to HTTPS

```bash
# HTTP should 301 redirect to HTTPS (not serve content)
curl -I http://freshmart.local

# Expected:
# HTTP/1.1 308 Permanent Redirect
# Location: https://freshmart.local
```

### Test 5 — Browser

Open `https://freshmart.local` in Chrome/Safari.

You'll see a warning ("Your connection is not private") because it's a self-signed CA not trusted by your OS. Click "Advanced → Proceed". The FreshMart store loads over HTTPS.

To remove the warning permanently, trust the CA cert:
```bash
# Extract the CA cert
kubectl get secret freshmart-ca-secret -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/freshmart-ca.crt

# On macOS: add to Keychain and trust it
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /tmp/freshmart-ca.crt
```

After trusting: `https://freshmart.local` shows a padlock with no warning.

### Test 6 — Certificate Auto-Renewal

cert-manager renews certificates 15 days before expiry automatically. You can simulate this:

```bash
# Check when cert renews
kubectl describe certificate freshmart-tls -n tesco-frontend | \
  grep -E "Not After|Renewal|Status"

# Force immediate renewal (for testing)
kubectl delete secret freshmart-tls -n tesco-frontend
# cert-manager detects the missing Secret and re-issues within ~30 seconds
kubectl get certificate -n tesco-frontend -w
```

### Test 7 — Verify cert-manager Components

```bash
# All cert-manager pods healthy
kubectl get pods -n cert-manager

# Events — see the cert issuance lifecycle
kubectl describe certificate freshmart-tls -n tesco-frontend | tail -20

# CertificateRequest (the actual CSR cert-manager sent to the issuer)
kubectl get certificaterequest -n tesco-frontend
kubectl get certificaterequest -n tesco-core
```

---

## Important cert-manager Commands

```bash
# List all certificates cluster-wide
kubectl get certificate -A

# List all certificate requests
kubectl get certificaterequest -A

# List all cluster issuers
kubectl get clusterissuer

# Check why a cert isn't ready
kubectl describe certificate <name> -n <namespace>
kubectl describe certificaterequest <name> -n <namespace>

# Manually trigger renewal
kubectl delete secret <cert-secret-name> -n <namespace>
# cert-manager re-issues automatically

# Check cert expiry from the Secret directly
kubectl get secret <name> -n <namespace> \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -dates

# View cert details
kubectl get secret freshmart-tls -n tesco-frontend \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

---

## CKS Exam Scenarios

### Scenario 1: "Configure TLS termination on the nginx Ingress"

The examiner gives you a running Ingress without TLS. Steps:
```bash
# 1. Create a TLS Secret (exam usually gives you the cert/key files)
kubectl create secret tls my-tls \
  --cert=tls.crt \
  --key=tls.key \
  -n target-namespace

# 2. Edit the Ingress to add TLS
kubectl edit ingress my-ingress -n target-namespace
# Add:
# spec:
#   tls:
#   - hosts: [example.com]
#     secretName: my-tls
```

### Scenario 2: "Install cert-manager and issue a self-signed certificate"

```bash
# Install
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml

# Create ClusterIssuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
EOF

# Create Certificate
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-cert
  namespace: default
spec:
  secretName: my-tls-secret
  dnsNames: [example.com]
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer
EOF
```

### Scenario 3: "Verify a certificate is valid and check its expiry"

```bash
kubectl get secret my-tls-secret -n default \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -text | grep -E "Not After|Subject|Issuer|DNS"
```

---

## cert-manager vs Manual TLS — CKS Mindset

| | Manual TLS | cert-manager |
|--|-----------|-------------|
| Cert creation | `openssl genrsa`, `openssl req` | Declare `Certificate` object |
| Renewal | Manual — you forget, cert expires, site down | Automatic — 15 days before expiry |
| Rotation | kubectl delete secret, recreate | Transparent — zero downtime |
| Audit | None | Every issuance logged as K8s Event |
| Scale | 1 cert = 1 manual process | 100 certs = same effort |
| Let's Encrypt | Manual ACME challenge | Automatic ACME via HTTP-01/DNS-01 |

**In production (EKS with real domain):**
```yaml
# Replace freshmart-ca-issuer with ACME Let's Encrypt
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: security@freshmart.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: nginx
```
One change to the `issuerRef` in your Certificate objects → real, browser-trusted certs. Zero other code changes.

---

## Additional Tests — Phase 4.8 Verification

### Test 8 — Confirm All Security Headers Are Present (matches your live output)

```bash
curl -k -I https://freshmart.local 2>/dev/null | grep -E \
  "strict-transport|x-frame|x-content|x-xss|referrer|permissions"

# Your confirmed output:
# strict-transport-security: max-age=31536000; includeSubDomains
# x-frame-options: DENY
# x-content-type-options: nosniff
# x-xss-protection: 1; mode=block
# referrer-policy: strict-origin-when-cross-origin
# permissions-policy: camera=(), microphone=(), geolocation=()
```

### Test 9 — Confirm HTTP Redirects to HTTPS

```bash
curl -I http://freshmart.local 2>/dev/null | grep -E "HTTP|Location"
# Expected:
# HTTP/1.1 308 Permanent Redirect
# Location: https://freshmart.local
```

### Test 10 — Confirm TLS Version (should be TLS 1.2 or 1.3 only)

```bash
# Check what TLS versions the server accepts
openssl s_client -connect freshmart.local:443 -tls1 2>&1 | grep -E "Protocol|Cipher|handshake"
# Expected: handshake failure (TLS 1.0 disabled)

openssl s_client -connect freshmart.local:443 -tls1_3 2>&1 | grep -E "Protocol|Cipher"
# Expected: TLSv1.3 accepted
```

### Test 11 — Confirm nginx hides server version

```bash
curl -k -I https://freshmart.local 2>/dev/null | grep -i server
# Expected: "server: nginx" (no version number) or header absent
# Bad (before): "Server: nginx/1.25.3" — version exposed
```

### Test 12 — Inspect the actual Certificate from the wire

```bash
# See exactly what cert nginx is serving
echo | openssl s_client -connect freshmart.local:443 -servername freshmart.local 2>/dev/null \
  | openssl x509 -noout -text \
  | grep -E "Issuer:|Subject:|Not Before|Not After|DNS:"

# Expected:
# Issuer: CN=freshmart-local-ca, O=FreshMart
# Subject: CN=freshmart.local, O=FreshMart
# Not After: ~90 days from now
# DNS: freshmart.local
```

### Test 13 — API still works over HTTPS

```bash
curl -sk https://freshmart.local/api/products | python3 -m json.tool | head -20
curl -sk https://freshmart.local/api/cart/test-session
```

---

## HashiCorp Vault for Secrets Management

### Why Vault? The Problem with Kubernetes Secrets

Kubernetes Secrets are **base64-encoded, not encrypted** (by default in etcd — we fixed this in Phase 4.2 with EncryptionConfiguration). But even with etcd encryption, K8s Secrets have fundamental problems:

```
Problems with plain K8s Secrets:
─────────────────────────────────
1. Any kubectl user with RBAC get/list on Secret can read all secrets
2. Secrets stored in Git (in CI/CD pipelines) — credentials leak
3. No secret rotation — changing a DB password means manual updates
4. No audit trail — who read which secret, when?
5. No dynamic credentials — static passwords that never expire
6. No multi-cluster sync — same secret in 5 clusters = 5 manual updates
```

Vault solves all of these.

### How HashiCorp Vault Works

```
┌─────────────────────────────────────────────────────────────────────────┐
│  HashiCorp Vault                                                         │
│                                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │  KV Secrets  │  │  Database    │  │  PKI Engine  │  │  Transit   │  │
│  │  Engine      │  │  Engine      │  │  (TLS certs) │  │  (encrypt) │  │
│  │  (static)    │  │  (dynamic)   │  │              │  │            │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └────────────┘  │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Auth Methods: Kubernetes SA token / LDAP / AWS IAM / OIDC      │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Audit Log: every read/write/revoke logged with who/when/what    │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### The Dynamic Secrets Pattern (most powerful Vault feature)

Instead of storing a static DB password, Vault **generates a temporary password on demand** and revokes it automatically:

```
Pod needs DB access:

  1. Pod authenticates to Vault using its K8s Service Account JWT
                │
                ▼
  2. Vault verifies the SA token with K8s API
                │
                ▼
  3. Vault connects to PostgreSQL and runs:
     CREATE ROLE v-pod-abc123 WITH LOGIN PASSWORD 'x7Kp...' VALID UNTIL '2026-06-07T13:00:00Z';
                │
                ▼
  4. Vault returns credentials to pod:
     { "username": "v-pod-abc123", "password": "x7Kp..." }
                │
                ▼
  5. Pod uses credentials for its lifetime (lease: 1 hour)
                │
                ▼
  6. Vault automatically revokes:
     DROP ROLE v-pod-abc123;

Result: credentials exist for exactly 1 hour, then gone. No static passwords.
```

### External Secrets Operator (ESO) — Vault + K8s Integration

In Kubernetes, you don't inject Vault directly into pods. You use **External Secrets Operator**, which syncs Vault secrets into K8s Secrets automatically:

```
┌──────────────┐      ┌─────────────────────┐      ┌────────────────┐
│  HashiCorp   │      │  External Secrets   │      │  Kubernetes    │
│  Vault       │      │  Operator (ESO)     │      │                │
│              │      │                     │      │                │
│  secret/     │◄─────│  ExternalSecret CR  │─────►│  Secret        │
│  freshmart/  │ read │  (every 1 hour,     │ sync │  db-credentials│
│  db-password │      │   reconcile)        │      │  (auto-updated)│
└──────────────┘      └─────────────────────┘      └────────────────┘
                                                           │
                                                           │ mounted as env/file
                                                           ▼
                                                    ┌─────────────┐
                                                    │  Pod        │
                                                    │  (reads     │
                                                    │  K8s Secret)│
                                                    └─────────────┘
```

The ExternalSecret CRD looks like this:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: tesco-core
spec:
  refreshInterval: 1h          # Sync from Vault every hour
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: db-credentials       # K8s Secret that gets created/updated
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: secret/freshmart/database
        property: url
```

Your pods reference the K8s Secret as normal. ESO handles the Vault interaction. Zero changes to application code.

---

## Real-World Secret Management — How Companies Do It

### Small/Mid-size Company (50–200 engineers)

```
Developer commits code
        │
        ▼
GitHub (no secrets in code — detected by Gitleaks in CI)
        │
        ▼
CI pipeline (GitHub Actions)
        │   reads from → GitHub Secrets (or AWS Secrets Manager)
        ▼
Docker image built + pushed to ECR
        │
        ▼
ArgoCD syncs Helm chart to EKS
        │
        ▼
External Secrets Operator syncs AWS Secrets Manager → K8s Secrets
        │
        ▼
Pod reads K8s Secret as env var or mounted file

TOOLS: GitHub Secrets / AWS Secrets Manager + ESO
```

### Large Enterprise (Netflix, Tesco, banks — 500+ engineers)

```
Platform Team owns Vault cluster (HA, 3+ nodes)
        │
        │  Kubernetes auth method enabled
        │  Each namespace has its own Vault policy
        │  Dynamic credentials for all databases
        │
Application Team declares ExternalSecret CR
        │
        ▼
ESO reads from Vault using the pod's ServiceAccount JWT
        │
        ▼
K8s Secret created/rotated automatically
        │
        ▼
Pod mounts Secret as file (NOT env var — env vars visible in /proc)

TOOLS: HashiCorp Vault Enterprise + External Secrets Operator
```

### Why Files > Environment Variables for Secrets

```
BAD — env var:
  kubectl exec pod -- env | grep DATABASE
  → DATABASE_URL=postgresql://user:pass@host/db
  (visible to anyone who can exec into pod)

GOOD — mounted file:
  kubectl exec pod -- cat /vault/secrets/database
  → Error: permission denied (file owned by root, app runs as uid 10001)
  (not accessible even to the pod's process tree)
```

In production: all secrets are mounted as files, never env vars.

---

## What Modern Companies Use Today (2025–2026)

### Secrets Management

| Tool | Who Uses It | Why |
|------|------------|-----|
| **HashiCorp Vault** | Banks, telcos, large enterprises | Full-featured, dynamic creds, audit log |
| **AWS Secrets Manager** | AWS-native companies | Simple, managed, no ops burden |
| **GCP Secret Manager** | GCP-native companies | Same as above for GCP |
| **Azure Key Vault** | Microsoft shops | Azure-native |
| **1Password Secrets Automation** | Startups, mid-size | Simple UI + K8s integration |

### TLS Certificate Management

| Tool | Who Uses It | Why |
|------|------------|-----|
| **cert-manager + Let's Encrypt** | Most K8s users | Free, automated, ACME |
| **cert-manager + Vault PKI** | Enterprises with internal CA | Full control over cert chain |
| **AWS ACM** | EKS + ALB users | Free, zero ops, auto-renews |
| **Cloudflare** | CDN-first companies | TLS at edge + DDoS protection |

### The Modern "Zero Trust" TLS Stack (what cutting-edge companies do)

```
External Traffic:
  Internet → Cloudflare (edge TLS) → ALB → K8s Ingress → Pod

Internal Traffic (service-to-service):
  Service Mesh (Istio / Linkerd) → mTLS automatically between every pod

Result: Every connection encrypted, both external and internal.
No unencrypted traffic anywhere in the cluster.
```

### Other Tools Companies Use Alongside cert-manager

**Service Mesh (mTLS for all inter-service communication):**
- **Istio** — full-featured, widely used, steep learning curve
- **Linkerd** — lightweight, simpler than Istio, CNCF graduated
- **Cilium** — eBPF-based, combines networking + security + observability

**Certificate Transparency / Policy:**
- **Venafi** — enterprise cert lifecycle management (used by banks)
- **cert-manager + policy controller** — validate certs meet org standards

**Ingress / API Gateway:**
- **Kong Gateway** — replaces nginx ingress with full API management
- **Traefik** — lightweight, auto-discovers K8s services
- **Envoy** — lower-level proxy (used by Istio/Linkerd internally)
- **AWS ALB Controller** — AWS-native, integrates with ACM

**PKI / Internal CA:**
- **HashiCorp Vault PKI engine** — issues certs, rotates CA, audit log
- **SPIFFE/SPIRE** — workload identity standard (used by Google, Uber)
- **AWS Private CA** — managed private CA on AWS

---

## The Full TLS + Secrets Picture for FreshMart

```
Current State (Phase 4.8):
──────────────────────────
Internet → nginx (TLS terminated, cert from cert-manager self-signed CA)
           → Services (plain HTTP internally)
           K8s Secrets for DB passwords (encrypted in etcd via Phase 4.2)

Target State (Phase 4.9 + 4.11):
──────────────────────────────────
Internet → nginx (TLS terminated, cert from Let's Encrypt on EKS)
           → Services communicating via mTLS (Phase 4.9)
           → payment-service: mutual TLS only from order-service
           Secrets: Vault dynamic credentials (Phase 4.11)
           Every secret has TTL, auto-rotates, full audit log

Production State (Phase 7 — EKS):
──────────────────────────────────
Internet → AWS ALB (TLS via ACM, free, auto-renews)
           → nginx ingress (internal TLS)
           → Istio/Linkerd mTLS mesh (all pod-to-pod traffic encrypted)
           Secrets via AWS Secrets Manager + External Secrets Operator
           Every DB credential dynamic (Vault) with 1-hour TTL
```

---

## Phase Progress

```
✅ Phase 4.1 — kube-bench CIS Hardening
✅ Phase 4.2 — etcd Encryption at Rest
✅ Phase 4.3 — Fine-grained RBAC
✅ Phase 4.4 — AppArmor Custom Profiles
✅ Phase 4.5 — Custom seccomp Profiles
✅ Phase 4.6 — OPA Gatekeeper
⏳ Phase 4.7 — Falco (deploy on EKS in Phase 7)
✅ Phase 4.8 — cert-manager + TLS Ingress (this phase)
⏳ Phase 4.9 — mTLS (order → payment)
⏳ Phase 4.10 — gVisor RuntimeClass
⏳ Phase 4.11 — Vault + External Secrets Operator
```
