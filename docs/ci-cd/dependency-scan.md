# CI/CD — Dependency Scanning

## Purpose
Dependency scanning checks third-party packages against known
vulnerability databases (CVEs), independent of anything wrong in this
project's own code. This complements SAST, which only
analyzes code actually written for this project; SAST has no
visibility into vulnerabilities shipped inside libraries this project
imports.

Unlike the deliberately planted application vulnerabilities in
`VULNERABILITIES.md`, dependency vulnerabilities here are not
hand-planted. They exist because each service pins older package
versions in its `requirements.txt`, and this stage is expected to
surface real, disclosed CVEs against those versions without any
seeding required.

## Tool: pip-audit
[pip-audit](https://github.com/pypa/pip-audit) is the official PyPA
tool for auditing Python dependencies against the OSV (Open Source
Vulnerabilities) database. Chosen over alternatives (Safety, Snyk) for
this stage because it requires no account, no API key, and no signup,
which keeps this stage self-contained like Bandit, unlike SonarCloud's
one-time setup requirement.

## Where It Runs
`.github/workflows/dependency-scan.yml` triggers on:
- `push` to `main` and any `feature/**` branch
- `pull_request` targeting `main`

A matrix strategy (`auth-service`, `transaction-service`, `frontend`)
runs one job per service, since each has its own independent
`requirements.txt`. `fail-fast: false` ensures one service's failure
doesn't cancel the others mid-run, so a single push always reports the
full picture across all three services.

## What This Should Catch
Given the currently pinned versions:

| Package | Pinned version | Service(s) |
|---|---|---|
| Flask | 2.2.2 | all three |
| PyJWT | 2.4.0 | auth-service |
| requests | 2.28.1 | frontend, transaction-service |
| psycopg2-binary | 2.9.5 | auth-service, transaction-service |

These are old enough that pip-audit is expected to surface at least
one disclosed CVE without any modification to the codebase. Treat
whatever pip-audit actually reports as authoritative over this table;
CVE databases are updated continuously and specific findings should be
verified against the workflow run, not assumed from this list.

## Report Artifacts
Each matrix job uploads a service-specific JSON report
(`pip-audit-<service>.json`) regardless of pass/fail, using the same
"run once permissively, then again strictly" pattern as the Bandit job
in SAST: a soft run (`|| true`) captures the report, then a second
strict run determines the actual job outcome.

## Why This Stays Red
Consistent with SAST, no automatic remediation happens in this
stage. Version bumps for vulnerable packages are deferred to the
technical article documenting this project, at which point pinned
versions will be updated and this stage is expected to turn green.

## Known Limitations
- Covers direct dependencies listed in `requirements.txt`. Transitive
  dependencies (dependencies of dependencies) not pinned explicitly
  are audited too by pip-audit, but version resolution can differ
  between a local `pip install` and what's actually running inside
  the Docker image; ideally this should be cross-checked against a
  lockfile or the built image itself (see container 
  scanning, which examines what's actually installed in the image).
- Vulnerability databases are point-in-time. A clean pip-audit run
  today doesn't guarantee no future disclosures against the same
  pinned versions; this is why the workflow runs on every push rather
  than once.
- Does not scan JavaScript/frontend dependencies, since this project
  has none outside the Python Flask stack.