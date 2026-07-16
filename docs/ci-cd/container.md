# CI/CD — Container Scanning

## Purpose
Container scanning inspects the actual built image, base OS packages,
installed libraries, and image configuration, rather than source code.
This stage targets the container-layer findings in `VULNERABILITIES.md`
directly: outdated base image (CK-01), and complements the Dockerfile
comments already in place for CK-02 (root user, no `HEALTHCHECK`).

SAST (issue #3) and dependency scanning (issue #4) only see what's
declared in source and `requirements.txt`. Neither has visibility into
what actually ends up inside the built image, transitive OS packages
pulled in by the base image, or drift between what's pinned and what's
actually installed at build time. Container scanning closes that gap.

## Tool: Trivy
[Trivy](https://github.com/aquasecurity/trivy) scans container images
for OS package vulnerabilities, language-level dependency
vulnerabilities baked into the image, misconfigurations, and secrets,
in a single pass. Already referenced as the intended tool for CK-01 in
this project's threat model docs.

## Where It Runs
`.github/workflows/container-scan.yml` triggers on:
- `push` to `main` and any `feature/**` branch
- `pull_request` targeting `main`

A matrix strategy (`auth-service`, `transaction-service`, `frontend`)
builds and scans each service's image independently, one job per
service, `fail-fast: false` so one service failing doesn't cancel
scanning of the others.

Each job:
1. Builds the image from that service's `Dockerfile`
2. Runs Trivy once permissively (`exit-code: 0`) to capture a full
   JSON report as an artifact regardless of outcome
3. Runs Trivy again strictly (`exit-code: 1`, `CRITICAL,HIGH` only) to
   determine the job's actual pass/fail state

This mirrors the pattern used in Bandit (issue #3) and pip-audit
(issue #4): always capture the full picture, but only fail the build
on severities that matter.

## Why `trivy-action` Is Pinned to a Commit SHA
```yaml
uses: aquasecurity/trivy-action@ed142fdd35a6dfd458986ceeff3542eb28291d1e # v0.36.0
```

This isn't the usual `@v6`-style tag pin used elsewhere in this
project's workflows. In March 2026, `aquasecurity/trivy-action`
suffered a real supply-chain compromise: an attacker with valid
publishing credentials force-pushed malicious code onto 75 of its 76
version tags, turning what looked like a normal tag reference
(`@v0.34.0`, for example) into a credential-stealing payload that ran
inside CI runners and exfiltrated secrets. Tags can be moved; a commit
SHA cannot.

Releases from `v0.35.0` onward are additionally protected by GitHub's
immutable releases feature, which prevents this specific class of tag
hijack going forward, but SHA-pinning remains the stronger guarantee
and costs nothing beyond an extra line of comment for readability.

This is a useful real-world example for the security case study this
project is building toward: even trusted, widely-used security
tooling is itself part of the supply chain, and needs the same
scrutiny as any other dependency.

## What This Should Catch
Given `FROM python:3.9-slim` in all three Dockerfiles (CK-01), Trivy
is expected to surface OS-level CVEs from the outdated base image's
package set. Exact CVE IDs will depend on the current Trivy
vulnerability database at scan time; treat the actual workflow output
as authoritative rather than any specific CVE list here, since new
disclosures land continuously.

## Why This Stays Red
Consistent with issues #3 and #4, no remediation happens in this
stage. Rebuilding on a current, patched base image is deferred to the
technical article documenting this project.

## Known Limitations
- Trivy scans what's in the image at build time; it has no visibility
  into runtime behavior (that's Falco's job, not currently a tracked
  pipeline stage).
- Does not catch Kubernetes manifest misconfigurations (missing
  resource limits, privileged pod specs, etc.) — that's IaC scanning,
  issue #6.
- A clean scan today doesn't guarantee a clean scan tomorrow against
  the same image; vulnerability databases update continuously, which
  is why this runs on every push rather than once.
- CK-02 (root user, no `HEALTHCHECK`) is documented in the Dockerfiles
  themselves but is a Dockerfile *configuration* issue, not a package
  vulnerability; Trivy's misconfiguration scanning can catch some of
  this class of issue but the primary fix is a Dockerfile change, not
  a scanning-stage change.