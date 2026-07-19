# Grants read-only access to the secureflow app's secrets, nothing else.
# Scoped as narrowly as possible: this policy cannot read any other
# path in Vault, cannot write, cannot delete, cannot manage Vault itself.

path "secret/data/secureflow/*" {
  capabilities = ["read"]
}
