# Phase 4.9 — mTLS (Mutual TLS): order-service → payment-service

**CKS Domain:** Minimize Microservice Vulnerabilities (20%)  
**Status:** ✅ Complete

---

## What Is mTLS?

Regular TLS proves **who the server is**. mTLS proves **who both sides are**.

```
Regular TLS (HTTPS):
  Client ──────────────────────────────────► Server
          "Are you really payment-service?"
          ← "Yes, here is my cert (signed by CA)"
          Client verifies server cert ✅
          Connection established.
  Problem: Server doesn't know WHO the client is.
           ANY service (or attacker) can call payment-service.

Mutual TLS (mTLS):
  Client ──────────────────────────────────► Server
          "Are you really payment-service?"
          ← "Yes. Are YOU really order-service?"
          "Yes, here is my cert (CN=order-service, signed by CA)"
          Both sides verify each other ✅
          Connection established.
  Result: ONLY order-service (proven by cert) can call payment-service.
          An attacker inside the cluster with no cert → TLS handshake rejected.
```

---

## FreshMart mTLS Design

```
┌─────────────────────────────────────────────────────────────────────────┐
│  tesco-core namespace                  tesco-payments namespace          │
│                                                                          │
│  ┌─────────────────┐    mTLS     ┌──────────────────────────────────┐   │
│  │  order-service  │────────────►│  payment-service                  │   │
│  │                 │             │                                    │   │
│  │  presents:      │             │  requires:                         │   │
│  │  tls.crt        │◄────────────│  tls.crt (server cert)            │   │
│  │  (CN=order-svc) │  TLS hand-  │  tls.key                          │   │
│  │  tls.key        │   shake     │  ca.crt (verify client)           │   │
│  │  ca.crt         │             │  verifies client CN = "order-svc" │   │
│  └─────────────────┘             └──────────────────────────────────┘   │
│                                                                          │
│  cert-manager issues both certs from freshmart-ca-issuer (Phase 4.8)    │
└─────────────────────────────────────────────────────────────────────────┘

NetworkPolicy (Phase 3):    Only order-service pod can reach payment-service:8004
mTLS (Phase 4.9):           Even if NetworkPolicy is bypassed, no cert = no connection
```

Two complementary controls:
- **NetworkPolicy** blocks at the network layer (L4) — unauthorized pods can't even connect
- **mTLS** blocks at the TLS layer (L7) — if somehow connected, no valid cert = rejected

---

## Certificate Design

| Certificate | Namespace | CommonName | Usage |
|-------------|-----------|-----------|-------|
| `payment-server-tls` | tesco-payments | `payment-service` | Server auth |
| `order-client-tls` | tesco-core | `order-service` | Client auth |

Both signed by `freshmart-ca-issuer` (our internal CA from Phase 4.8).

The server cert has all K8s DNS SANs:
```
payment-service
payment-service.tesco-payments
payment-service.tesco-payments.svc
payment-service.tesco-payments.svc.cluster.local
```

---

## Files Changed / Created

```
k8s/15-mtls/
├── 00-certificates.yaml        ← cert-manager certs (server + client)
├── 01-configmap-patches.yaml   ← env vars: MTLS_ENABLED, cert file paths
└── 02-deployment-patches.yaml  ← mount /certs volume in both deployments

services/payment-service/main.go    ← added buildMTLSConfig() + mTLS server
services/order-service/app/main.py  ← updated _process_payment() with cert=

infra/kind/setup-mtls.sh            ← install script
```

---

## How to Deploy

```bash
cd ~/Downloads/DevSecOps\ Projects/CKS-\ Real\ case/freshmart-platform

chmod +x infra/kind/setup-mtls.sh
./infra/kind/setup-mtls.sh
```

The script:
1. Issues both certs via cert-manager
2. Patches ConfigMaps with mTLS env vars
3. Rebuilds both Docker images (Go + Python with mTLS code)
4. Loads new images into Kind
5. Patches deployments to mount `/certs` volume
6. Restarts both deployments
7. Verifies mTLS is active from pod logs

---

## Manual Testing

### Test 1 — Certificates are Ready

```bash
kubectl get certificate -n tesco-payments
kubectl get certificate -n tesco-core

# Expected:
# NAMESPACE        NAME                 READY   SECRET               AGE
# tesco-payments   payment-server-tls   True    payment-server-tls   1m
# tesco-core       order-client-tls     True    order-client-tls     1m
```

### Test 2 — Cert Files Mounted in Pods

```bash
# payment-service — server cert
PAYMENT_POD=$(kubectl get pod -n tesco-payments -l app=payment-service \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec $PAYMENT_POD -n tesco-payments -- ls -la /certs/
# Expected: tls.crt tls.key ca.crt (mode 0400)

# order-service — client cert
ORDER_POD=$(kubectl get pod -n tesco-core -l app=order-service \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec $ORDER_POD -n tesco-core -- ls -la /certs/
```

### Test 3 — payment-service Started with mTLS

```bash
kubectl logs $PAYMENT_POD -n tesco-payments | grep -i mtls

# Expected:
# Payment service listening with mTLS on :8004 (client CN required: order-service)
```

### Test 4 — Verify the mTLS Handshake from order-service pod

```bash
ORDER_POD=$(kubectl get pod -n tesco-core -l app=order-service \
  -o jsonpath='{.items[0].metadata.name}')

# Full mTLS handshake — present client cert, verify server cert with CA
kubectl exec $ORDER_POD -n tesco-core -- \
  openssl s_client \
    -connect payment-service.tesco-payments.svc.cluster.local:8004 \
    -cert /certs/tls.crt \
    -key /certs/tls.key \
    -CAfile /certs/ca.crt \
    -verify_return_error \
    -brief 2>&1

# Expected output:
# CONNECTION ESTABLISHED
# Protocol version: TLSv1.3
# Ciphersuite: TLS_AES_256_GCM_SHA384
# Peer certificate: CN=payment-service, O=FreshMart
# Hash used: SHA256
# Signature type: ECDSA
# Verification: OK        ← server cert verified against our CA
```

### Test 5 — Reject Connection WITHOUT Client Certificate

```bash
# Try connecting without a client cert — should be rejected
kubectl exec $ORDER_POD -n tesco-core -- \
  openssl s_client \
    -connect payment-service.tesco-payments.svc.cluster.local:8004 \
    -CAfile /certs/ca.crt \
    -brief 2>&1

# Expected:
# SSL_connect: ... alert handshake failure
# CONNECTION FAILURE
# Reason: server requires client certificate (RequireAndVerifyClientCert)
```

### Test 6 — End-to-End Checkout Still Works

```bash
# The full checkout flow should work over mTLS transparently
curl -sk https://freshmart.local/api/orders \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "mtls-test",
    "delivery_address": {
      "full_name": "mTLS Test",
      "address_line1": "123 Secure St",
      "city": "London",
      "postcode": "SW1A 1AA"
    },
    "payment_details": {
      "card_number": "4242424242424242",
      "expiry": "12/27",
      "cvv": "123"
    }
  }' | python3 -m json.tool

# Expected: order created successfully — mTLS is transparent to the caller
```

### Test 7 — View Cert Details

```bash
# Inspect the server cert
kubectl get secret payment-server-tls -n tesco-payments \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -text | grep -E "Subject:|Issuer:|DNS:|Not After"

# Expected:
# Subject: CN=payment-service, O=FreshMart
# Issuer: CN=freshmart-local-ca, O=FreshMart
# DNS: payment-service, payment-service.tesco-payments, ...
# Not After: <90 days from now>

# Inspect the client cert
kubectl get secret order-client-tls -n tesco-core \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -text | grep -E "Subject:|Issuer:|Extended Key|Not After"

# Expected:
# Subject: CN=order-service, O=FreshMart
# Extended Key Usage: TLS Web Client Authentication
```

### Test 8 — Confirm mTLS in payment-service Logs

```bash
# After a checkout request, payment-service logs should show mTLS auth
kubectl logs -n tesco-payments -l app=payment-service --since=2m | \
  grep -E "mTLS|client authenticated|REJECTED"

# Expected on success:
# mTLS OK: client authenticated — CN=order-service

# Expected if wrong cert (would never happen in normal flow):
# mTLS REJECTED: client CN="product-service" (expected "order-service")
```

---

## Code Changes Explained

### Go payment-service — `buildMTLSConfig()`

```go
tlsConfig := &tls.Config{
    Certificates: []tls.Certificate{serverCert}, // our server cert

    // MUTUAL TLS: require + verify client cert
    ClientAuth: tls.RequireAndVerifyClientCert,
    ClientCAs:  caPool,  // only certs signed by our CA are accepted

    MinVersion: tls.VersionTLS12,

    // Extra identity check: CN must be "order-service"
    VerifyPeerCertificate: func(_, verifiedChains ...) error {
        clientCN := verifiedChains[0][0].Subject.CommonName
        if clientCN != "order-service" {
            return fmt.Errorf("unauthorized client: %s", clientCN)
        }
        return nil  // only order-service passes
    },
}
```

The `ClientAuth: tls.RequireAndVerifyClientCert` is the key line. Go's TLS stack handles the entire handshake — the handler code never runs for unauthorized clients.

### Python order-service — `_process_payment()`

```python
# httpx native mTLS support:
async with httpx.AsyncClient(
    cert=(mtls_cert, mtls_key),  # present our client cert
    verify=mtls_ca               # verify server cert against our CA
) as client:
    resp = await client.post(url, json=data)
```

`cert=` and `verify=` are standard httpx parameters. No custom SSL code needed.

---

## CKS Exam Scenarios

### Scenario 1: "Configure mTLS between two services"

On the exam, you'd typically use Istio to enable mTLS. The minimal approach:

```bash
# Enable mTLS in Istio's PeerAuthentication
cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: tesco-payments
spec:
  mtls:
    mode: STRICT   # reject all non-mTLS connections
EOF
```

Our manual approach demonstrates the same concept at a lower level — useful for understanding what Istio does automatically.

### Scenario 2: "Only allow service A to call service B"

```yaml
# AuthorizationPolicy (Istio) — only order-service SA can call payment-service
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: payment-only-from-order
  namespace: tesco-payments
spec:
  selector:
    matchLabels:
      app: payment-service
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/tesco-core/sa/order-service-sa"]
```

Our manual CN check does the same thing without Istio.

### Scenario 3: "Verify mTLS is working"

```bash
# From within the cluster — the exam way
kubectl exec -n tesco-core deploy/order-service -- \
  openssl s_client \
    -connect payment-service.tesco-payments.svc.cluster.local:8004 \
    -cert /certs/tls.crt \
    -key /certs/tls.key \
    -CAfile /certs/ca.crt 2>&1 | grep -E "Verify return|Protocol|CN"
```

---

## mTLS in Real Production

### Manual (what we built) vs Service Mesh

| Approach | Setup | Cert Rotation | Observability | Who uses it |
|----------|-------|---------------|---------------|-------------|
| Manual (our approach) | Per-service code changes | cert-manager auto-renews | App logs | Good for learning |
| Istio | Sidecar injection | Automatic | Full metrics/traces | Google, Lyft, major enterprises |
| Linkerd | Lightweight proxy | Automatic | Built-in dashboard | Mid-size companies |
| Cilium mTLS | eBPF-based | Automatic | Hubble UI | Modern cloud-native |

### Why Companies Use Service Meshes

In a 100-service architecture, writing mTLS into every service like we did is not scalable. Service meshes inject a **sidecar proxy** (Envoy/Linkerd-proxy) into every pod:

```
Without service mesh:         With Istio/Linkerd:
─────────────────────         ──────────────────────────────
order-service pod             order-service pod
  [app code]                    [app code] ← still plain HTTP internally
    │ plain HTTP                 [envoy sidecar] ← handles mTLS transparently
    ▼                               │ mTLS
payment-service pod                 ▼
  [app code + TLS code]         payment-service pod
                                  [envoy sidecar] ← verifies client cert
                                  [app code] ← still plain HTTP internally
```

The app code stays simple. The mesh handles all TLS, cert rotation, and policy.

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
✅ Phase 4.8 — cert-manager + TLS Ingress
✅ Phase 4.9 — mTLS order → payment (this phase)
⏳ Phase 4.10 — gVisor RuntimeClass
⏳ Phase 4.11 — Vault + External Secrets Operator
```
