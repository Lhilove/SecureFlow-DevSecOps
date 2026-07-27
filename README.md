# SecureFlow — Vulnerable Banking Platform

> **This is an INTENTIONALLY INSECURE baseline.**
> Do not deploy to a real cloud account. Run only in an isolated lab or local
> Kubernetes cluster (kind, k3s, minikube).

This repository is the "before" state for the SecureFlow DevSecOps case study.
Your job is to build the security pipeline, remediations, policy enforcement,
secrets management, runtime monitoring, and observability described in the
project brief. What you fork is broken on purpose — every vulnerability listed
in [`VULNERABILITIES.md`](./VULNERABILITIES.md) is real and exploitable.

Read the project brief PDF end-to-end before you touch any code.

---

## Architecture

```
                     ┌────────────────────┐
                     │     frontend       │  Flask + Jinja2 on :5000
                     │  (server-rendered) │
                     └──────┬───────┬─────┘
                            │       │
                 calls       │       │  calls
                            ▼       ▼
            ┌─────────────────┐  ┌──────────────────────┐
            │  auth-service   │  │ transaction-service  │
            │   Flask :5001   │  │    Flask :5002       │
            └────────┬────────┘  └──────────┬───────────┘
                     │                      │
                     ▼                      ▼
              ┌────────────┐          ┌────────────────┐
              │  auth-db   │          │ transaction-db │
              │ postgres   │          │   postgres     │
              └────────────┘          └────────────────┘
```

Three Python/Flask services, two independent PostgreSQL instances, microservices
pattern. Each service has its own database so that per-service Vault policies
(Step 14 of the brief) are meaningful — compromising one service does not grant
access to another service's data.

---

## Quick Start — Docker Compose

```bash
docker-compose up --build

# Services are then available at:
#   frontend              http://localhost:5000
#   auth-service API      http://localhost:5001
#   transaction-service   http://localhost:5002
#   auth-db               localhost:5432
#   transaction-db        localhost:5433
```

Seed users (the password hashes are MD5 — weak on purpose, see AV-05):

| Username | Password   | Role  |
|----------|-----------|-------|
| admin    | admin123  | admin |
| alice    | alice123  | user  |
| bob      | bob123    | user  |

---

## Quick Start — Kubernetes (base manifests)

```bash
kubectl apply -k infra/kubernetes/base

# Everything will apply because there is no admission controller in the way.
# That is the point. One of your tasks is to install OPA Gatekeeper and watch
# the base manifests get rejected.

kubectl get pods -n secureflow -w
```

---

## Example Exploits

Once the stack is running, these should all succeed against the baseline:

```bash
BASE=http://localhost:5001

# AV-01 — SQL injection auth bypass. Logs in as admin with no password.
curl -s -X POST $BASE/login \
  -H 'Content-Type: application/json' \
  -d '{"username": "admin'\''--", "password": "anything"}'

# Save the token from the response, then:
TOKEN=<paste token here>

# TV-01 — IDOR. Read admin's balance from alice's account.
curl -s http://localhost:5002/balance/1 \
  -H "Authorization: Bearer $TOKEN"

# TV-03 — Negative transfer. Drains the recipient.
curl -s -X POST http://localhost:5002/transfer \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"from_account": 2, "to_account": 3, "amount": -500}'

# FV-01 — Reflected XSS via query string.
# Open in browser after logging in as alice:
#   http://localhost:5000/dashboard?msg=<script>alert(document.cookie)</script>
```

---

## What's In This Repository

```
secureflow/
├── .env                              ← IV-04: committed on purpose, 5 secrets
├── docker-compose.yml                ← IV-01/02/03/06/07 + CK-03
├── .gitignore                        ← deliberately does not exclude .env
├── README.md                         ← this file
├── VULNERABILITIES.md                ← the full index keyed to the PDF
├── services/
│   ├── auth-service/                 ← AV-01..AV-08
│   ├── transaction-service/          ← TV-01..TV-07
│   └── frontend/                     ← FV-01..FV-07 (except FV-04)
├── db/
│   ├── auth/init.sql                 ← users schema + seed
│   └── transaction/init.sql          ← accounts, transactions, cards + seed
└── infra/
    ├── kubernetes/base/              ← CK-02..CK-09
    └── terraform/                    ← IV-08, IV-09, IV-10 + the modules Checkov will scan
```

# SecureFlow DevSecOps — Solution Implementation

A complete DevSecOps pipeline implementation built on top of the
[SecureFlow vulnerable baseline](https://github.com/Dcoder21/SecureFlow-VulnerableCodebase).
This repository contains the security pipeline, policy enforcement, secrets
management, runtime monitoring, and observability layers described in the
project brief all proven working against the intentionally vulnerable
codebase.

---

## Pipeline Status

| Workflow | Status |
|---|---|
| CI Pipeline | ![CI](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/ci.yml/badge.svg) |
| Secret Scanning | ![Secrets](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/secrets-scan.yml/badge.svg) |
| SAST | ![SAST](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/sast.yml/badge.svg) |
| Dependency Scanning | ![Deps](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/dependency-scan.yml/badge.svg) |
| Container Scanning | ![Container](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/container-scan.yml/badge.svg) |
| IaC Scanning | ![IaC](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/iac-scan.yml/badge.svg) |
| DAST | ![DAST](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/dast.yml/badge.svg) |
| Security Gate | ![Gate](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/security-gate.yml/badge.svg) |
| Image Signing | ![Sign](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/sign-image.yml/badge.svg) |
| OPA Gatekeeper | ![OPA](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/gatekeeper.yml/badge.svg) |
| Falco | ![Falco](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/falco.yml/badge.svg) |
| HashiCorp Vault | ![Vault](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/vault.yml/badge.svg) |
| Network Policies | ![Network](https://github.com/Lhilove/SecureFlow-DevSecOps/actions/workflows/network-policies.yml/badge.svg) |

---

## Architecture

Developer → git push → GitHub Repository
│
▼
CI Pipeline (GitHub Actions)
├── [Stage 1 — Parallel Scans]
│ ├── Gitleaks — secrets detection
│ ├── Bandit + SonarCloud — SAST
│ ├── pip-audit — dependency scanning
│ ├── Trivy — container + IaC scanning
│ └── Checkov — Terraform + Kubernetes IaC policy
│
├── [Stage 2 — Dynamic Testing]
│ └── OWASP ZAP — DAST against deployed application
│
├── [Stage 3 — Security Gate]
│ └── Aggregates all scan results — blocks on CRITICAL, warns on HIGH
│
├── [Stage 4 — Supply Chain]
│ ├── Cosign — image signing
│ └── SBOM — SPDX attestation
│
└── [Stage 5 — Deploy to kind + Runtime Security]
├── OPA Gatekeeper — admission control
├── Falco — runtime threat detection
├── HashiCorp Vault — secrets injection
└── Network Policies — default deny + whitelist


---

## What This Repository Adds

Everything in this list was built on top of the vulnerable baseline:

.github/
└── workflows/
├── ci.yml — pipeline entry point
├── secrets-scan.yml — Gitleaks secrets detection
├── sast.yml — Bandit + SonarCloud
├── dependency-scan.yml — pip-audit
├── container-scan.yml — Trivy image scanning
├── iac-scan.yml — Checkov Terraform + Kubernetes
├── dast.yml — OWASP ZAP
├── security-gate.yml — aggregation and gate decision
├── sign-image.yml — Cosign + SBOM
├── deploy.yml — kind cluster deployment
├── gatekeeper.yml — OPA Gatekeeper constraints
├── falco.yml — runtime threat detection
├── vault.yml — HashiCorp Vault secrets management
└── network-policies.yml — Kubernetes network policy enforcement

infra/
├── falco/
│ └── values.yaml — custom Falco rules including Write below binary dir
└── kubernetes/
└── (Gatekeeper constraints, NetworkPolicies)

pipeline/
└── scripts/
└── security-gate.sh; gate aggregation script

docs/
└── ci-cd/
├── ci.md
├── falco.md
└── (per-workflow documentation)


---

## Pipeline Design Decisions

**Why scans report but do not block on this baseline:**
The vulnerable codebase is intentionally broken; MD5 passwords, SQLi,
debug mode, publicly accessible RDS, wildcard IAM policies. Every scanner
finds real issues by design. Blocking on findings at this stage would make
the pipeline impossible to run. The correct approach is:

1. Prove detection: show every tool finds what it should find
2. Remediate: fix the vulnerabilities in the application and infrastructure
3. Enforce: turn blocking gates back on and prove clean scans pass

This repository demonstrates Step 1. Remediation and enforcement are
documented in the article series.

**Security gate logic:**
The gate aggregates workflow conclusions via the GitHub API for the exact
commit SHA. Blocking workflows (Gitleaks, SAST, Container, IaC) must pass.
DAST is warn-only. "Not run" is treated as non-blocking.

**Falco driver:**
`modern_ebpf`: no kernel module compilation, works on GitHub Actions
runners (kernel 5.8+), reliable in kind clusters where pods share the
host kernel.

---

## Threat Model

A full STRIDE threat model covering the CI/CD pipeline, Kubernetes cluster,
Auth Service, and Transaction Service is in the companion repository:
[Secureflow-DevSecOps](https://github.com/Lhilove/Secureflow-DevSecOps)

---

## Article Series

This repository is documented across a Medium series:

- Part 1: Shift Left, Verify Right: Building Security That Does Not Slow Down Development
- Part 2: Implementing Shift Left, Verify Right in a Vulnerable FinTech Microservices Application
- Part 3: Threat Modeling a FinTech Microservices Application: Where DevSecOps Really Begins
- Part 4: Integrating CI/CD Security Tools: SAST, DAST, IaC, and More (in progress)

---

## Baseline Repository

The intentionally vulnerable application this pipeline runs against:
[Dcoder21/SecureFlow-VulnerableCodebase](https://github.com/Dcoder21/SecureFlow-VulnerableCodebase)

---

## Safety Notes

- Do not `terraform apply` against a real AWS account. IAM policies use
  `AdministratorAccess` and RDS instances are publicly accessible by design.
- The `.env` file contains example AWS keys that will trigger secret scanners.
  This is intentional, Gitleaks is supposed to catch them.
- Deleting a secret from a later commit does not remove it from git history.

---

## Disclaimer

This repository is built for educational and professional development purposes.
All security findings are against an intentionally vulnerable application.
No production systems were tested without authorization.