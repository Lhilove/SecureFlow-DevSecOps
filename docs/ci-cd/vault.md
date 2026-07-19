# CI/CD — HashiCorp Vault (Secrets Management)

## What This Fixes
IV-01 and IV-03: secrets hardcoded in Terraform variables and committed
`.env`/ConfigMap values. Right now, `AUTH_DB_PASSWORD`, `TX_DB_PASSWORD`,
and `JWT_SECRET` live as plaintext in a Kubernetes ConfigMap, which
isn't encrypted at rest in etcd by default, and can be read by anyone
with `kubectl get configmap` access in the namespace. Vault replaces
that with centrally stored, encrypted secrets that are injected into
pods at runtime, never written into any manifest, ConfigMap, or `.env`
file at all.

## Why Persistent Storage, Not Dev Mode
Vault has a "dev mode" (`vault server -dev`) that starts already
unsealed with a throwaway root token, useful for a five-minute demo but
skips the actual mechanism that makes Vault secure. This project uses
`server.dev.enabled: false` with file-backed persistent storage, which
means Vault starts **sealed** and has to go through the real
init/unseal sequence every production Vault deployment requires.

## Core Concepts

### Sealed vs Unsealed
A freshly initialized Vault stores all its data encrypted at rest. In
its "sealed" state, Vault physically cannot decrypt anything, including
its own configuration, even for an administrator with API access. It
has to be "unsealed" with the encryption key before it can serve any
request. This is Vault's core security property: compromising the
underlying storage (a stolen disk, a database dump) gets an attacker
nothing without the unseal key too.

### Shamir's Secret Sharing (and why this project uses one key)
Real production Vault deployments split the unseal key into multiple
"key shares" (commonly 5), requiring a threshold (commonly 3) of them
to reconstruct the key. No single person can unseal Vault alone. This
project's `vault-init.sh` uses `-key-shares=1 -key-threshold=1`, one
key, deliberately. That multi-person threat model exists to prevent any
single compromised operator from unsealing Vault; it doesn't apply to
an ephemeral CI cluster with no human operators and a lifetime measured
in minutes. The script still exercises the real init → unseal →
configure sequence, just simplified for automation. A real deployment
of this project would use the standard multi-share setup.

### KV v2 Secrets Engine
Vault's key-value secrets engine, version 2, which adds versioning
(previous values of a secret are retained and can be rolled back) on
top of a basic path-based read/write store. Secrets are written to
`secret/data/secureflow/*` and organized by what they belong to
(`auth-db`, `transaction-db`, `jwt`).

### Policies
An HCL document defining exactly what paths a given identity can
access and with what capabilities. `infra/vault/policies/secureflow-policy.hcl`
grants `read` only, on `secret/data/secureflow/*` only. It cannot write,
delete, list other paths, or manage Vault itself. Least privilege, by
design: even if this policy's associated credential were somehow
misused, the blast radius is "can read three specific secrets," not
"has any meaningful control over Vault."

### Kubernetes Auth Method
Instead of distributing a separate Vault credential to every pod (which
just recreates the original problem, a secret needed to get secrets),
Vault's Kubernetes auth method lets a pod authenticate using its own
Kubernetes-issued service account token, something it already has
automatically, with no extra secret to manage or leak. Vault verifies
that token against the Kubernetes API (`TokenReview`) and, if it maps
to a bound role, issues a short-lived Vault token scoped to that role's
policy.

### The Agent Injector
A mutating admission webhook (similar in mechanism to Gatekeeper,
though for a completely different purpose) that watches for pods
carrying specific `vault.hashicorp.com/*` annotations. When it sees
one, it automatically adds an init container and a sidecar container
to the pod, before the pod's own containers ever start. That sidecar
authenticates to Vault using the pod's own service account token,
fetches the requested secret, and writes it to a shared, in-memory
volume mounted at `/vault/secrets/`. The application container reads
its secret from a local file; it never talks to Vault directly, and
the secret never appears in any Kubernetes object at all, not the Pod
spec, not a ConfigMap, not anywhere `kubectl get` could expose it.

## Where and How This Is Applied
Only `auth-service` is annotated in this stage, applied at deploy time
via `kubectl patch`, not committed into `infra/kubernetes/base`, the
same pattern already used for the `imagePullPolicy` fix in the Local
Kubernetes Deploy stage. `base/` stays as the deliberately broken
baseline; this is a proof that the mechanism works for one service,
not a full remediation of every service's secrets yet.

## How the Workflow Verifies This Actually Works
The test doesn't just confirm the sidecar container exists, it reads
the actual file the sidecar wrote (`/vault/secrets/db-password`) from
inside the running pod and compares it byte-for-byte against the value
that was written into Vault in the first step. A pass here means the
full chain worked: Vault stored the secret correctly, the Kubernetes
auth method correctly authorized the pod, the Agent Injector correctly
fetched and wrote it, and the value made it through unmodified.

## Known Limitations
- Only `auth-service` receives injected secrets in this stage.
  `transaction-service` and `frontend` still read from the ConfigMap.
  Extending injection to all three is straightforward (same annotation
  pattern) but not done here, this stage proves the mechanism, not a
  full migration.
- `infra/vault/policies/secureflow-policy.hcl` and the policy embedded
  in `vault-init.sh` are currently two copies of the same content that
  must be kept in sync manually. In a more mature setup, the script
  would read the `.hcl` file directly (e.g. via `kubectl cp` into the
  Vault pod) rather than duplicating it inline.
- Single key share/threshold, as discussed above, appropriate for this
  ephemeral CI context, not for a real production deployment.
- No TLS between the app and Vault in this setup
  (`tls_disable = true`), acceptable for an isolated in-cluster CI test,
  not acceptable for any real deployment; a production Vault always
  terminates TLS.
- The root token generated by `vault operator init` has unlimited
  access to everything in Vault. It's used here only to bootstrap the
  policy and auth method, then discarded when the cluster tears down.
  A real deployment would revoke or tightly control root token usage
  after initial setup.