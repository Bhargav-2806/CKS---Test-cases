#!/usr/bin/env bash
# =============================================================================
# Phase 4.11 — HashiCorp Vault + External Secrets Operator
# CKS Domain: Minimize Microservice Vulnerabilities (20%)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
step()  { echo -e "\n${CYAN}══ $* ══${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/../.."
K8S_DIR="$ROOT/k8s/17-vault-eso"
VAULT_NAMESPACE="tesco-security"
VAULT_TOKEN="freshmart-vault-root"
VAULT_ADDR="http://127.0.0.1:8200"
DB_URL="postgresql://freshmart:freshmart@postgresql.tesco-data.svc.cluster.local:5432/freshmart"

# ─── Step 1: Verify cluster ───────────────────────────────────────────────────
step "Checking Kind cluster"
kubectl cluster-info --context kind-freshmart-cks > /dev/null 2>&1 || \
  fail "Kind cluster not found."
ok "Cluster found"

# ─── Step 2: Create tesco-security namespace ─────────────────────────────────
step "Creating tesco-security namespace"
kubectl create namespace "$VAULT_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$VAULT_NAMESPACE" \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite
ok "Namespace $VAULT_NAMESPACE ready"

# ─── Step 3: Install HashiCorp Vault ─────────────────────────────────────────
step "Installing HashiCorp Vault (dev mode)"
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update hashicorp

if helm status vault -n "$VAULT_NAMESPACE" &>/dev/null; then
  info "Vault already installed — skipping"
else
  helm install vault hashicorp/vault \
    --namespace "$VAULT_NAMESPACE" \
    --values "$ROOT/security/vault/vault-values.yaml" \
    --wait \
    --timeout=120s
  ok "Vault installed"
fi

# ─── Step 4: Install External Secrets Operator ───────────────────────────────
step "Installing External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update external-secrets

if helm status external-secrets -n external-secrets &>/dev/null; then
  info "ESO already installed — skipping"
else
  # Apply RBAC first (creates external-secrets namespace + vault-token Secret)
  kubectl apply -f "$K8S_DIR/00-vault-eso-rbac.yaml"

  helm install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --set installCRDs=true \
    --wait \
    --timeout=120s
  ok "External Secrets Operator installed"
fi

# ─── Step 5: Configure Vault ─────────────────────────────────────────────────
step "Configuring Vault (secrets engine + policies + secrets)"

VAULT_POD=$(kubectl get pod -n "$VAULT_NAMESPACE" -l app.kubernetes.io/name=vault \
  -o jsonpath='{.items[0].metadata.name}')
info "Vault pod: $VAULT_POD"

# Helper function — exec vault commands in the pod
vault_exec() {
  kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -- \
    env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$VAULT_TOKEN" \
    vault "$@"
}

# 5a — Enable KV-v2 secrets engine
info "Enabling KV-v2 secrets engine..."
vault_exec secrets enable -path=secret kv-v2 2>/dev/null || \
  info "KV-v2 already enabled — continuing"
ok "KV-v2 enabled at path: secret/"

# 5b — Write FreshMart secrets into Vault
info "Writing database credentials to Vault..."
vault_exec kv put secret/freshmart/database \
  url="$DB_URL" \
  username="freshmart" \
  password="freshmart" \
  db="freshmart"
ok "Secrets written to vault kv: secret/freshmart/database"

# 5c — Create read policy for FreshMart secrets
info "Creating Vault policy..."
vault_exec policy write freshmart-read-policy - << 'POLICY'
# FreshMart read policy — allows reading all freshmart/* secrets
# Applied to: ESO token, service account roles
path "secret/data/freshmart/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/freshmart/*" {
  capabilities = ["read", "list"]
}
POLICY
ok "Policy 'freshmart-read-policy' created"

# 5d — Enable K8s auth method (for production use + demo)
info "Enabling Kubernetes auth method..."
vault_exec auth enable kubernetes 2>/dev/null || \
  info "K8s auth already enabled — continuing"

KUBE_HOST="https://kubernetes.default.svc.cluster.local"
vault_exec write auth/kubernetes/config \
  kubernetes_host="$KUBE_HOST"
ok "K8s auth configured"

# 5e — Create K8s auth role for ESO
info "Creating Vault K8s auth role for ESO..."
vault_exec write auth/kubernetes/role/eso-role \
  bound_service_account_names="external-secrets" \
  bound_service_account_namespaces="external-secrets" \
  policies="freshmart-read-policy" \
  ttl="1h"
ok "K8s auth role 'eso-role' created"

# ─── Step 6: Verify secrets written correctly ─────────────────────────────────
step "Verifying secrets in Vault"
vault_exec kv get secret/freshmart/database
ok "Vault secrets verified"

# ─── Step 7: Apply ESO resources ─────────────────────────────────────────────
step "Applying ClusterSecretStore and ExternalSecrets"

# RBAC first (includes vault-token Secret for ESO auth)
kubectl apply -f "$K8S_DIR/00-vault-eso-rbac.yaml"

# ClusterSecretStore (ESO connection to Vault)
kubectl apply -f "$K8S_DIR/01-secretstore.yaml"

info "Waiting for ClusterSecretStore to be ready..."
sleep 5
kubectl wait clustersecretstore/vault-backend \
  --for=condition=Ready \
  --timeout=60s || warn "SecretStore not ready yet — check: kubectl describe clustersecretstore vault-backend"

# ExternalSecrets (sync Vault → K8s Secrets)
kubectl apply -f "$K8S_DIR/02-externalsecrets.yaml"

info "Waiting for ESO to sync secrets from Vault (30s)..."
sleep 30

# ─── Step 8: Migrate from Phase 3 plain K8s Secrets ─────────────────────────
step "Migrating: deleting Phase 3 plain K8s Secrets (ESO will recreate from Vault)"

# NOTE: ESO's ExternalSecrets use creationPolicy: Owner.
# If the K8s Secret already exists and is NOT owned by ESO,
# ESO cannot adopt it. We delete the old ones first.
# ESO recreates them immediately from Vault data.

for ns_secret in "tesco-core:db-credentials" "tesco-payments:db-credentials" "tesco-data:postgresql-credentials"; do
  NS="${ns_secret%%:*}"
  SECRET="${ns_secret##*:}"

  # Check if secret is already ESO-owned
  OWNER=$(kubectl get secret "$SECRET" -n "$NS" \
    -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || echo "none")

  if [ "$OWNER" = "ExternalSecret" ]; then
    ok "$NS/$SECRET already owned by ESO — skipping"
  else
    kubectl delete secret "$SECRET" -n "$NS" --ignore-not-found
    info "Deleted $NS/$SECRET (ESO will recreate from Vault)"
  fi
done

info "Waiting for ESO to recreate secrets (15s)..."
sleep 15

# ─── Step 9: Verify ESO-managed secrets ──────────────────────────────────────
step "Verifying ESO-managed secrets"
kubectl get externalsecret -A

for ns_secret in "tesco-core:db-credentials" "tesco-payments:db-credentials" "tesco-data:postgresql-credentials"; do
  NS="${ns_secret%%:*}"
  SECRET="${ns_secret##*:}"
  STATUS=$(kubectl get secret "$SECRET" -n "$NS" \
    -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || echo "missing")
  if [ "$STATUS" = "ExternalSecret" ]; then
    ok "$NS/$SECRET ← managed by ESO (owned by ExternalSecret)"
  else
    warn "$NS/$SECRET not yet ESO-owned (status: $STATUS)"
  fi
done

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Phase 4.11 — Vault + ESO COMPLETE"
echo "══════════════════════════════════════════════════════════════"
echo ""
info "Vault pod:"
kubectl get pods -n "$VAULT_NAMESPACE"
echo ""
info "ESO pods:"
kubectl get pods -n external-secrets
echo ""
info "ExternalSecrets status:"
kubectl get externalsecret -A
echo ""
echo "  Vault UI (port-forward):"
echo "  kubectl port-forward -n $VAULT_NAMESPACE svc/vault 8200:8200"
echo "  http://localhost:8200  (token: $VAULT_TOKEN)"
echo ""
echo "  Read a secret from Vault CLI:"
echo "  kubectl exec -n $VAULT_NAMESPACE \$(kubectl get pod -n $VAULT_NAMESPACE"
echo "    -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')"
echo "    -- env VAULT_TOKEN=$VAULT_TOKEN VAULT_ADDR=http://127.0.0.1:8200"
echo "    vault kv get secret/freshmart/database"
echo ""
echo "  See PHASE-4.11-VAULT-ESO.md for full guide"
echo "══════════════════════════════════════════════════════════════"
