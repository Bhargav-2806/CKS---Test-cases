# Phase 4.2 — etcd Encryption at Rest

> **Project:** FreshMart CKS DevSecOps Portfolio
> **Phase:** 4.2 of 8 — etcd Encryption at Rest
> **Tool:** Kubernetes EncryptionConfiguration (native — no external tool needed)
> **Cluster:** `freshmart-cks` (Kind — 1 control-plane + 2 workers)
> **CKS Domain:** Cluster Hardening (15%)
> **kube-bench Fixes:** 1.2.27 + 1.2.28

---

## What Is etcd Encryption at Rest?

By default, Kubernetes stores all objects (Secrets, ConfigMaps, Pods, etc.) in etcd as **plain base64-encoded bytes**. Anyone with access to the etcd data directory — a rogue admin, a backup thief, a compromised node — can read every Secret value directly from disk without going through the API server.

**etcd encryption at rest** makes the API server encrypt Secret (and ConfigMap) data **before writing to etcd**, and decrypt it **on read**. etcd stores ciphertext. The encryption key lives only in `/etc/kubernetes/encryption-config.yaml` on the control plane.

**CKS exam relevance:** This is directly tested. Expect tasks like:
- *"Configure the API server to encrypt Secrets at rest using aescbc"*
- *"Verify that a specific Secret is encrypted in etcd"*
- *"Rotate the encryption key"*

---

## How It Works — The Full Picture

```
WITHOUT encryption (Phase 3 state):

   kubectl get secret           etcd disk (/var/lib/etcd)
          │                           │
          ▼                           ▼
     API server ──────────────►  plaintext bytes
                                 "postgresql://freshmart:freshmart@..."
                                        ↑
                                 attacker reads this
                                 directly from disk or backup


WITH encryption (Phase 4.2):

   kubectl get secret           etcd disk (/var/lib/etcd)
          │                           │
          ▼                           ▼
     API server ──decrypt──────►  k8s:enc:aescbc:v1:key1:Ω∂ƒ¬˚∆©®...
          │          ↑                       ↑
          │     AES-256 key            encrypted ciphertext
          │   (only in encryption-     (useless without the key)
          │    config.yaml on CP)
          ▼
   "postgresql://freshmart..."  ← only the API server ever sees plaintext
```

### Request Flow After Encryption

```
WRITE (kubectl create secret):
  kubectl → API server → encrypt with AES key → write ciphertext to etcd

READ (kubectl get secret):
  etcd → ciphertext → API server → decrypt with AES key → return plaintext to kubectl

DIRECT etcd read (attacker bypassing API server):
  etcd → ciphertext → ??? (no key) → unreadable binary
```

---

## Encryption Providers (CKS Reference)

| Provider | Algorithm | Key Size | CKS Exam Use | Notes |
|----------|-----------|----------|--------------|-------|
| `identity` | None (plaintext) | — | Default state | No encryption — remove as first provider after migration |
| `aescbc` | AES-CBC + PKCS#7 | 32 bytes | ✅ Exam standard | Widely tested on CKS |
| `secretbox` | XSalsa20-Poly1305 | 32 bytes | Alternative | Stronger than aescbc |
| `aesgcm` | AES-GCM | 16/24/32 bytes | Rarely tested | Key rotation requires restart |
| `kms` | Cloud KMS | Managed | Production | AWS KMS, GCP CKMS — Phase 7 |

**Provider order matters:**
- **First provider** = used to **encrypt new writes**
- **Subsequent providers** = used to **decrypt reads** (for migration from old keys)

---

## What We Implemented

### Files Created

```
freshmart-platform/
├── k8s/09-etcd-encryption/
│   └── encryption-config.yaml          ← Template (no real key — for Git)
└── infra/kind/
    └── setup-etcd-encryption.sh        ← Generates key + applies encryption
```

### EncryptionConfiguration (`k8s/09-etcd-encryption/encryption-config.yaml`)

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets       # ← encrypt all Secret objects
      - configmaps    # ← also encrypt ConfigMaps
    providers:
      - aescbc:
          keys:
            - name: freshmart-key-1
              secret: <32-byte-base64-key>  # generated at deploy time
      - identity: {}  # ← fallback: allows reading pre-existing unencrypted data
```

### kube-apiserver flags added

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml (on control plane)
- --encryption-provider-config=/etc/kubernetes/encryption-config.yaml
```

Plus a `hostPath` volume + `volumeMount` so the config file is accessible inside the kube-apiserver static pod.

---

## How to Apply

```bash
cd ~/Downloads/DevSecOps\ Projects/CKS-\ Real\ case/freshmart-platform

chmod +x infra/kind/setup-etcd-encryption.sh
./infra/kind/setup-etcd-encryption.sh
```

### What the script does (7 steps)

```
Step 1 → Generate 32-byte random AES key (head -c 32 /dev/urandom | base64)
Step 2 → Build EncryptionConfiguration YAML with the real key
Step 3 → Copy config to /etc/kubernetes/encryption-config.yaml on control plane (chmod 600)
Step 4 → Patch kube-apiserver.yaml — add flag + volumeMount + hostPath volume
Step 5 → Wait for API server to restart (~15–30s, kubelet detects manifest change)
Step 6 → Force re-encrypt ALL existing Secrets and ConfigMaps in every namespace
Step 7 → Verify by reading db-credentials directly from etcd with etcdctl
```

> **Critical — Step 6:** Enabling encryption only encrypts **new writes**. Existing secrets remain plaintext until explicitly replaced. The script runs `kubectl get secrets --all-namespaces -o json | kubectl replace -f -` which forces the API server to re-write (and therefore encrypt) every secret.
>
> **Skipping Step 6 is the most common CKS exam mistake.**

---

## Verification — Practical Tests

### Test 1 — Confirm the API server has the encryption flag

```bash
docker exec freshmart-cks-control-plane \
  grep "encryption-provider-config" \
  /etc/kubernetes/manifests/kube-apiserver.yaml
```

**Expected:**
```
- --encryption-provider-config=/etc/kubernetes/encryption-config.yaml
```

---

### Test 2 — View the live encryption config on the control plane

```bash
docker exec freshmart-cks-control-plane \
  cat /etc/kubernetes/encryption-config.yaml
```

**Expected:** `aescbc` as first provider with a base64 key, `identity` as fallback.

---

### Test 3 — THE KEY TEST: Read a Secret directly from etcd

This bypasses the API server entirely — no decryption. You see raw etcd bytes.

```bash
docker exec freshmart-cks-control-plane sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/tesco-core/db-credentials \
  | strings | head -5
'
```

**Expected (encrypted — PASS):**
```
k8s:enc:aescbc:v1:freshmart-key-1:...binary garbage...
```

**What it looked like before (plaintext — FAIL):**
```
k8s

v1Secret
...
DATABASE_URL
postgresql://freshmart:freshmart@postgresql.tesco-data...  ← readable!
```

---

### Test 4 — Confirm API server still decrypts transparently for workloads

```bash
kubectl get secret db-credentials -n tesco-core \
  -o jsonpath='{.data.DATABASE_URL}' | base64 -d
```

**Expected:** `postgresql://freshmart:freshmart@postgresql.tesco-data.svc.cluster.local:5432/freshmart`

Encryption is completely transparent to applications. The API server handles encryption and decryption invisibly.

---

### Test 5 — Create a NEW secret and immediately verify it's encrypted

```bash
# Create a test secret
kubectl create secret generic encryption-test \
  --from-literal=api-key="my-very-secret-api-key-12345" \
  --namespace=default

# Read it directly from etcd — should NOT contain "my-very-secret-api-key-12345"
docker exec freshmart-cks-control-plane sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/default/encryption-test \
  | strings | grep -c "my-very-secret-api-key-12345" \
  && echo "FAIL: secret value visible in etcd!" \
  || echo "PASS: secret value NOT visible in etcd (encrypted)"
'

# Confirm it's readable via API server (decryption working)
kubectl get secret encryption-test -n default \
  -o jsonpath='{.data.api-key}' | base64 -d
```

**Expected:**
```
PASS: secret value NOT visible in etcd (encrypted)
my-very-secret-api-key-12345   ← API server decrypts correctly
```

```bash
# Clean up
kubectl delete secret encryption-test -n default
```

---

### Test 6 — Verify ALL FreshMart secrets are encrypted

```bash
for SECRET_PATH in \
  "/registry/secrets/tesco-core/db-credentials" \
  "/registry/secrets/tesco-payments/db-credentials" \
  "/registry/secrets/tesco-data/postgresql-credentials"; do
  echo -n "=== $SECRET_PATH → "
  docker exec freshmart-cks-control-plane sh -c "
    ETCDCTL_API=3 etcdctl \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key \
      get $SECRET_PATH 2>/dev/null | strings | head -1
  "
done
```

**Expected — all 3 lines start with:**
```
=== /registry/secrets/tesco-core/db-credentials → k8s:enc:aescbc:v1:freshmart-key-1:...
=== /registry/secrets/tesco-payments/db-credentials → k8s:enc:aescbc:v1:freshmart-key-1:...
=== /registry/secrets/tesco-data/postgresql-credentials → k8s:enc:aescbc:v1:freshmart-key-1:...
```

---

### Test 7 — Simulated attacker view (hex dump of etcd data)

```bash
docker exec freshmart-cks-control-plane sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/tesco-core/db-credentials \
  | xxd | head -15
'
```

**Expected:** Pure hex — completely unreadable without the AES key.

---

### Test 8 — List all secret paths in etcd (keys only, no values)

```bash
docker exec freshmart-cks-control-plane sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets --prefix --keys-only
'
```

Shows all secret paths stored in etcd — useful for auditing what secrets exist.

---

## Important Commands Reference

### Apply / re-apply encryption

```bash
# Re-encrypt all secrets after key rotation or new secret creation
kubectl get secrets --all-namespaces -o json | kubectl replace -f -

# Re-encrypt all configmaps
kubectl get configmaps --all-namespaces -o json | kubectl replace -f -
```

### Inspect control plane config

```bash
# View live encryption config on control plane
docker exec freshmart-cks-control-plane cat /etc/kubernetes/encryption-config.yaml

# Confirm API server has picked up the flag (live process)
docker exec freshmart-cks-control-plane \
  ps aux | grep kube-apiserver | tr ' ' '\n' | grep encryption

# Watch API server restart after manifest edit
watch kubectl get pods -n kube-system
```

### etcdctl commands

```bash
# Read specific secret (raw)
docker exec freshmart-cks-control-plane sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/<namespace>/<secret-name> | strings | head -3
'

# List all keys under a path
docker exec freshmart-cks-control-plane sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry --prefix --keys-only | head -30
'

# Count total secrets in etcd
docker exec freshmart-cks-control-plane sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets --prefix --keys-only | wc -l
'
```

---

## CKS Exam Scenarios

### Scenario 1 — "Encrypt Secrets at rest using aescbc"

```bash
# 1. Generate key
KEY=$(head -c 32 /dev/urandom | base64)

# 2. Create config on control plane
cat > /tmp/enc.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources: [secrets]
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${KEY}
      - identity: {}
EOF
scp /tmp/enc.yaml <control-plane>:/etc/kubernetes/encryption-config.yaml

# 3. Add flag to kube-apiserver.yaml
# Edit: /etc/kubernetes/manifests/kube-apiserver.yaml
# Add:  - --encryption-provider-config=/etc/kubernetes/encryption-config.yaml

# 4. Wait for restart, then re-encrypt
kubectl get secrets -A -o json | kubectl replace -f -

# 5. Verify
ETCDCTL_API=3 etcdctl get /registry/secrets/default/mysecret | strings | head -2
# Must show: k8s:enc:aescbc:v1:key1:...
```

---

### Scenario 2 — "Rotate the encryption key"

```bash
# 1. Add new key as FIRST, keep old key as SECOND
# In encryption-config.yaml:
#   providers:
#     - aescbc:
#         keys:
#           - name: key2          ← new key (encrypts new writes)
#             secret: <new-key>
#           - name: key1          ← old key (still decrypts old data)
#             secret: <old-key>
#     - identity: {}

# 2. Restart API server (edit the manifest to trigger reload)

# 3. Re-encrypt everything with new key
kubectl get secrets -A -o json | kubectl replace -f -

# 4. Remove old key (all data now encrypted with key2)
# In encryption-config.yaml: remove key1 entry

# 5. Restart API server again
```

---

### Scenario 3 — "Verify a Secret is encrypted in etcd"

```bash
# The exam will name a specific secret to verify
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/<namespace>/<name> | head -c 50

# PASS: output starts with k8s:enc:aescbc:v1:
# FAIL: output contains readable text
```

---

### Scenario 4 — "Disable encryption and restore plaintext" (exam edge case)

```bash
# Make identity the FIRST provider so new writes are plaintext
# providers:
#   - identity: {}     ← first = encrypts new writes (plaintext)
#   - aescbc:          ← second = still decrypts old encrypted data
#       keys: ...

# Re-encrypt everything (now written as plaintext)
kubectl get secrets -A -o json | kubectl replace -f -

# Verify: etcd should now show readable text
```

---

## What We Achieved

| Before Phase 4.2 | After Phase 4.2 |
|-----------------|-----------------|
| Secrets in etcd: base64 plaintext | Secrets in etcd: AES-256-CBC ciphertext |
| Anyone with etcd access reads secrets | etcd access shows unreadable binary |
| kube-bench 1.2.27: WARN | kube-bench 1.2.27: addressed |
| kube-bench 1.2.28: WARN | kube-bench 1.2.28: addressed |
| Backup theft = data breach | Backup theft = encrypted binary |

---

## Important Caveats

**1. The key is not backed up automatically**
The encryption key lives in `/etc/kubernetes/encryption-config.yaml` inside the Kind container. If the cluster is deleted, the key is gone — and so is the ability to read the encrypted data. In production (Phase 7 EKS), use AWS KMS or Vault as the key provider.

**2. Encryption is at the API server layer, not etcd layer**
etcd itself has no knowledge of encryption. It stores whatever bytes the API server sends. The API server is the only component that knows the key.

**3. kube-apiserver restart is required**
Any change to the EncryptionConfiguration (new key, new provider) requires the API server to restart to pick it up. In Kind, this happens automatically when the static pod manifest changes.

**4. identity fallback must be removed eventually**
The `identity: {}` fallback allows reading pre-existing unencrypted data. Once all secrets are re-encrypted (Step 6), you should remove `identity` from the providers list — otherwise, an attacker who gains API server write access could downgrade encryption by creating an unencrypted secret.

---

## Phase 4.2 Complete — What's Next

```
✅ Phase 4.1 — kube-bench CIS Hardening
✅ Phase 4.2 — etcd Encryption at Rest
⏳ Phase 4.3 — Fine-grained RBAC (Roles per service)
⏳ Phase 4.4 — AppArmor custom profiles
⏳ Phase 4.5 — Custom seccomp profiles
⏳ Phase 4.6 — OPA Gatekeeper (policy-as-code)
⏳ Phase 4.7 — Falco (runtime threat detection)
⏳ Phase 4.8 — cert-manager + TLS Ingress
⏳ Phase 4.9 — mTLS (order → payment)
⏳ Phase 4.10 — gVisor RuntimeClass
⏳ Phase 4.11 — Vault + External Secrets Operator
```
