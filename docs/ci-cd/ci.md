# CI/CD — Pipeline Entry Point (ci.yml)

## What This Does

`ci.yml` is the pipeline entry point for the SecureFlow DevSecOps
platform. Every push to `main` or a `feature/**` branch, and every
pull request targeting `main`, causes this workflow to fire first. Its
job is not to run scans itself each scan has its own dedicated
workflow but to act as the visible, named trigger that anchors the
entire pipeline in the GitHub Actions tab and documents the stage
ordering that every other workflow participates in.

Think of it as the conductor: it does not play any instrument, but its
presence establishes when the music starts and makes the order of play
legible to anyone reading the Actions log.

## Pipeline Stage Order

The architecture diagram shows a sequential pipeline. In practice,
GitHub Actions runs event-triggered workflows in parallel by default.
The sequencing is enforced through two mechanisms:

| Mechanism | Where it applies |
|---|---|
| `workflow_run` dependencies | Security Gate waits for all scan workflows to complete before evaluating results |
| Logical ordering in ci.yml echo output | Documents the intended stage order for humans reading the Actions tab |

The intended order is:
[Stage 1: Parallel Scans]
Secret Scanning (Gitleaks)
Static Analysis (Bandit + SonarCloud)
Dependency Scanning (pip-audit)
Container Scanning (Trivy)
IaC Scanning (Checkov; Terraform + Kubernetes)

[Stage 2: Dynamic Testing]
DAST (OWASP ZAP) runs against the deployed application

[Stage 3: Gate]
Security Gate aggregates all Stage 1 and Stage 2 results
blocks on CRITICAL, warns on HIGH

[Stage 4: Supply Chain]
Image Signing (Cosign)
SBOM Generation (SPDX)

[Stage 5: Deploy]
Deploy to kind cluster

[Stage 6: Runtime Security, parallel]
Falco runtime threat detection
HashiCorp Vault secrets injection
Network Policies enforcement
OPA Gatekeeper admission control


## What This Does Not Do

`ci.yml` does not:

- Run any security scan itself
- Make any blocking or passing decision
- Push or deploy anything

All of that belongs to the individual workflow files. `ci.yml`
exists because a pipeline without a named entry point is harder to
reason about, audit, and explain to stakeholders. Having a single
workflow that fires on every push and documents the full stage order
in one place is a deliberate operational choice.

## Relationship to the Security Gate

The Security Gate (`security-gate.yml`) uses `workflow_run` triggers
to wait for all scan workflows to complete before evaluating results.
This means the gate cannot be bypassed by pushing directly — it always
evaluates the actual output of the scans, not a cached or stale result.

`ci.yml` and the Security Gate together form the bookends of the
pipeline: ci.yml marks the start, the Security Gate marks the
decision point.

## Relationship to the Architecture Diagram

The CI Pipeline block in the SecureFlow architecture diagram maps
directly to the workflows this entry point coordinates:

Developer → git push → GitHub Repository → CI Pipeline (this file)
→ [Parallel Scans] → Security Gate → ECR → EKS


Every arrow in that block corresponds to a workflow in
`.github/workflows/`. This file is the arrow from the repository to
the pipeline.

## Known Limitations

- GitHub Actions does not natively support strict sequential workflow
  chaining across separate workflow files without `workflow_run`
  dependencies. The stage ordering documented here is logical, not
  enforced at the workflow scheduler level for Stage 1 workflows,
  which all run in parallel.
- If a Stage 1 workflow is skipped (branch filter, path filter, or
  manual disable), the Security Gate will see it as "not run" rather
  than "passed" or "failed". The gate script handles this by treating
  "not run" as non-blocking for WARN workflows and as a pass for
  BLOCKING workflows that genuinely did not need to run.