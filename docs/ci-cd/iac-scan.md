# CI/CD — IaC Scanning

## Purpose
IaC scanning inspects infrastructure definitions, Terraform and
Kubernetes manifests, for misconfigurations before they're ever
applied to a real cloud account. This stage targets the
infrastructure-layer findings in `VULNERABILITIES.md`: public subnets
and public EKS API endpoint (IV-10), plus the broader IV-08/IV-09
category of infrastructure misconfiguration this project catalogues.

Unlike SAST or dependency scanning, which examine application code and
libraries, this stage examines what the infrastructure *would become*
if deployed, without ever needing to actually deploy it. Checkov reads
the Terraform and Kubernetes definitions statically.

## Tool: Checkov
[Checkov](https://github.com/bridgecrewio/checkov) scans Terraform,
Kubernetes manifests, and several other IaC formats against a large
built-in policy set covering AWS, Azure, and GCP misconfigurations.
Already named as the intended tool for this stage in this project's
Terraform comments (`infra/terraform/main.tf` explicitly notes
"Checkov should block it in the pipeline") and threat model docs.

## Where It Runs
`.github/workflows/iac-scan.yml` triggers on:
- `push` to `main` and any `feature/**` branch
- `pull_request` targeting `main`

Two independent jobs run in parallel:

| Job | Scope | Directory |
|---|---|---|
| `checkov-terraform` | AWS infrastructure definitions | `infra/terraform` |
| `checkov-kubernetes` | K8s manifests (Deployments, Services, etc.) | `infra/kubernetes` |

Each job follows the same "report permissively, then fail strictly"
pattern used in Bandit, pip-audit, and Trivy: one soft-fail run
captures a full JSON report as an artifact, then a second strict run
determines the job's actual pass/fail outcome.

## What This Should Catch
Given the planted issues already commented directly in
`infra/terraform/main.tf`:

- **IV-10**: EKS nodes and API endpoint in public subnets
  (`modules/eks/main.tf`, `modules/vpc/main.tf`)
- Broader misconfigurations across IAM, S3, and RDS modules, expected
  to surface as Checkov's standard `CKV_AWS_*` check IDs

For Kubernetes, expect findings around missing resource limits,
absence of `securityContext` restrictions, and default-namespace usage
if any manifests fall back to defaults rather than the dedicated
`namespace.yaml`.

Treat actual Checkov output as authoritative over any specific check
ID list here, the built-in policy set updates independently of this
project.

## Why This Stays Red
Consistent with issues #2 through #5, no remediation happens in this
stage. This Terraform tree is explicitly marked "DO NOT terraform
apply this against a real AWS account" in its own header comment,
Checkov failing here is the pipeline doing its job, not a bug.
Fixing the underlying Terraform/K8s definitions is deferred to the
technical article documenting this project.

## Known Limitations
- Static analysis of IaC definitions doesn't catch drift, if someone
  manually changes a resource in the AWS console after `apply`,
  Checkov scanning the Terraform source won't see it. That's a
  separate problem (cloud posture management), out of scope here.
- Checkov's Kubernetes checks operate on the manifests as written; if
  Kustomize overlays (`kustomization.yaml`) change values at apply
  time, Checkov scanning the base manifests alone won't reflect the
  final rendered output. Worth revisiting if overlays are added later.
- Admission-time enforcement (OPA Gatekeeper, blocking a
  misconfigured resource from actually being scheduled onto a
  cluster) is a separate, later control and not covered by this
  stage, this stage only catches issues before merge, not at deploy
  time.