# CI/CD — Security Gate

## Purpose
Every scanning stage built so far (Gitleaks, SAST, Container Scanning,
IaC Scanning, DAST) makes its own pass/fail decision in isolation. This
project's architecture diagram shows a different shape: a single
Security Gate sitting downstream of all scanners, making one
aggregated decision, "block on CRITICAL, warn on HIGH", before an
image is allowed to proceed to signing and deployment.

Without this stage, there's no single place that says "is this commit
actually safe to move forward," only a scattered set of independently
red or green checks a person has to manually reconcile.

## Design: Aggregation via `workflow_run`, Not a Monolith
There were two ways to build this:

1. **Rewrite every scanning workflow as a reusable workflow**
   (`workflow_call`) and have one orchestrator workflow call all of
   them, then gate on their combined `needs.*.result`. This is the
   "correct" long-term architecture, but means touching and re-testing
   seven already-working, already-verified workflow files.
2. **Leave every existing scanning workflow untouched**, and build a
   separate aggregator that triggers on their completion
   (`workflow_run`) and queries their results via the GitHub API.

This project uses approach 2. It's a deliberate tradeoff: lower risk
(nothing that already works gets touched or re-broken), faster to
build and verify, at the cost of being a slightly less "native"
GitHub Actions pattern than a single unified pipeline.

## How It Works
`.github/workflows/security-gate.yml` triggers whenever any of five
named workflows complete (`workflow_run`, `types: [completed]`):
Gitleaks, SAST, Container Scanning, IaC Scanning, DAST.

When triggered, the gate:
1. Reads `github.event.workflow_run.head_sha`, the commit the
   triggering workflow just ran against
2. Queries the GitHub Actions API (`gh api .../actions/runs`) for all
   workflow runs against that same commit
3. Checks the conclusion of each of the five tracked workflows
4. Classifies them:
   - **Blocking**: Gitleaks, SAST, Container Scanning, IaC Scanning:
     a `failure` conclusion here fails the gate
   - **Warn-only**: DAST: a `failure` conclusion is reported in the
     summary but does not fail the gate
5. Writes a markdown table to the GitHub Actions job summary showing
   every workflow's conclusion
6. Exits non-zero (failing the gate job) if any blocking workflow
   failed

## Why DAST Is Warn-Only Here
This mirrors a real-world judgment call, not just this project's
"stay red" convention. DAST findings (missing headers, CSRF gaps) are
real but generally lower severity and higher false-positive-prone than
a hard-coded secret, a critical SAST finding, or a container running a
CVE-laden base image. Treating DAST as blocking from day one would
make the gate too noisy to be useful; most real pipelines mature DAST
into a blocking stage only after its findings have been triaged and
tuned over time.

## Why This Gate Will Show BLOCKED Right Now
This is expected, not a bug. Bandit (SAST) and Checkov (IaC) both
already exit non-zero against this intentionally vulnerable codebase,
consistent with every prior stage's "stay red until the technical
article" approach. The gate is the first stage that actually *acts* on
that redness by refusing to pass, rather than just reporting it in
isolation. A BLOCKED gate right now means the pipeline is working
correctly, not that something is broken.

## Known Limitations
- **Workflow-level granularity, not finding-level severity.** This
  gate treats "did the SAST job fail" as its blocking signal, not
  "does the SAST report contain a CRITICAL finding specifically." The
  architecture diagram's "block on CRITICAL, warn on HIGH" implies
  parsing each tool's report and checking actual severity fields
  (Trivy's `CRITICAL`/`HIGH`, Checkov's severity metadata, etc.),
  which this version does not do. A stage currently either fully
  passes or fully fails as a unit; there's no middle ground captured
  here. Building true severity-level aggregation (a script that
  downloads each stage's JSON/SARIF artifact and checks specific
  severity fields) is a reasonable future enhancement.
- **`workflow_run` only fires for workflow files present on the
  default branch.** This gate cannot be tested by pushing to a feature
  branch alone; `security-gate.yml` itself must be merged to `main`
  first, since GitHub evaluates `workflow_run` triggers against the
  version of the workflow file on the default branch, not the branch
  that triggered the upstream workflow.
- **Race conditions on rapid pushes.** If a commit triggers all five
  scanning workflows and the gate fires multiple times (once per
  completing workflow) before all five have finished, an early gate
  run may see "not run" for a workflow that's still in progress rather
  than its real conclusion. For a small project with this few
  concurrent runs this is a minor risk, but worth knowing about before
  relying on this pattern at larger scale.
- **No branch protection integration yet.** The gate reports a
  pass/fail status, but nothing currently requires that status to pass
  before a PR can be merged. Wiring this into GitHub's branch
  protection rules (as a required status check) would be the next
  step to make this actually block merges, not just report on them.