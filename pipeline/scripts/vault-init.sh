#!/usr/bin/env bash
# vault-init.sh
#
# Initializes, unseals, and configures a freshly deployed Vault server
# for the secureflow application. This is the real init/unseal flow
# (not dev mode), run once against a brand-new Vault instance with no
# existing state.
#
# Single key share/threshold is used deliberately for this CI/kind
# context — a real production Vault uses multiple key shares (Shamir's
# Secret Sharing) held by different people, so no single person can
# unseal Vault alone. That threat model doesn't apply to an ephemeral
# CI cluster torn down at the end of the job, so this simplifies to one
# key for automation, while still exercising the real init -> unseal ->
# configure sequence.
#
# Required environment variables:
#   VAULT_ADDR      - e.g. http://127.0.0.1:8200 (port-forwarded)
#   AUTH_DB_PASSWORD, TX_DB_PASSWORD, JWT_SECRET - secret values to store
#
# Writes VAULT_TOKEN (root token) to $GITHUB_ENV if running in Actions,
# so subsequent steps can use it.

set -euo pipefail

: "${VAULT_ADDR:?VAULT_ADDR is required}"
: "${AUTH_DB_PASSWORD:?AUTH_DB_PASSWORD is required}"
: "${TX_DB_PASSWORD:?TX_DB_PASSWORD is required}"
: "${JWT_SECRET:?JWT_SECRET is required}"

echo "== Initializing Vault =="
INIT_OUTPUT=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)
UNSEAL_KEY=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')

echo "== Unsealing Vault =="
vault operator unseal "$UNSEAL_KEY"

export VAULT_TOKEN="$ROOT_TOKEN"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "VAULT_TOKEN=$ROOT_TOKEN" >> "$GITHUB_ENV"
fi

echo "== Enabling KV v2 secrets engine =="
vault secrets enable -path=secret kv-v2 || echo "(already enabled)"

echo "== Writing secureflow secrets =="
vault kv put secret/secureflow/auth-db password="$AUTH_DB_PASSWORD"
vault kv put secret/secureflow/transaction-db password="$TX_DB_PASSWORD"
vault kv put secret/secureflow/jwt secret="$JWT_SECRET"

echo "== Applying least-privilege policy =="
vault policy write secureflow-policy - <<'POLICY'
path "secret/data/secureflow/*" {
  capabilities = ["read"]
}
POLICY

echo "== Enabling Kubernetes auth method =="
vault auth enable kubernetes || echo "(already enabled)"

# Vault runs in-cluster, so it can reach the Kubernetes API directly
# via the standard in-cluster service discovery env vars.
vault write auth/kubernetes/config \
  kubernetes_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"

echo "== Binding secureflow namespace's service account to the policy =="
vault write auth/kubernetes/role/secureflow-role \
  bound_service_account_names=default \
  bound_service_account_namespaces=secureflow \
  policies=secureflow-policy \
  ttl=1h

echo "== Vault initialization complete =="