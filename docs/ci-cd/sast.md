# CI/CD — Static Analysis (SAST)

## Purpose
Static analysis inspects source code without executing it, catching
vulnerability patterns before code merges. This stage targets the
application-layer findings in `VULNERABILITIES.md` directly: SQL
injection (AV-01, AV-02), weak password hashing (AV-05), reflected and
stored XSS (FV-01, FV-02), and hardcoded secrets that Gitleaks' entropy
rules might miss (AV-07, low-entropy JWT secret).

Two tools run in this stage, each catching a different class of issue:

| Tool | Scope | Why |
|---|---|---|
| Bandit | Python/Flask-specific security lint | Fast, free, purpose-built for exactly the patterns in this codebase (SQL string concatenation, `hashlib.md5`, `eval`, hardcoded binds) |
| SonarCloud | Broader SAST + code quality | Matches the threat model's stated tooling (`01-ci-cd-pipeline.md`), covers a wider rule set, tracks findings over time on a dashboard |

## Where It Runs
`.github/workflows/sast.yml` triggers on:
- `push` to `main` and any `feature/**` branch
- `pull_request` targeting `main`

Two independent jobs run in parallel: `bandit` and `sonarcloud`. Either
failing should block a merge; they're not redundant; they catch
different things.

## Job 1: Bandit
```bash
bandit -r services/ --severity-level medium --confidence-level medium
```

Scans all three Flask services. Findings below medium severity or
medium confidence are not treated as blocking, since this codebase is
intentionally vulnerable and a strict low/low threshold would surface
noise unrelated to the tracked vulnerability IDs.

The workflow runs Bandit twice: once with `|| true` to capture a JSON
report as an artifact regardless of outcome, then again without the
override so the step's actual exit code determines pass/fail. This
keeps the report available for review even on a failing run.

Expected findings this should catch on the current codebase:
- `B608`: SQL injection via string-built queries (AV-01, AV-02)
- `B303`/`B324`: use of insecure hash functions, e.g. MD5 (AV-05)
- `B105`/`B106`: hardcoded password/secret strings (AV-07, FV-03)

## Job 2: SonarCloud
Requires one-time setup before this job passes:
1. Import the repository at [sonarcloud.io](https://sonarcloud.io)
2. Generate a token under **My Account → Security**
3. Add it as a repo secret named `SONAR_TOKEN`
4. Turn off "Automatic Analysis" in the SonarCloud project settings,
   since analysis is driven from this workflow instead

Project metadata (organization key, project key, source paths) lives
in `sonar-project.properties` at the repo root rather than in the
workflow file, which is the convention for non-Maven/Gradle projects.

```properties
sonar.projectKey=<your project key>
sonar.organization=<your organization key>
sonar.sources=services
```

`fetch-depth: 0` on checkout is recommended by SonarSource for more
accurate reporting (blame/history-aware analysis), not strictly
required for a first scan.

## Why the Quality Gate Isn't Blocking Yet
SonarCloud's own Quality Gate (bugs/vulnerabilities/coverage
thresholds) is left informational for now rather than blocking the
workflow. This is intentional at this stage of the project: the
codebase is deliberately vulnerable end to end, so a fresh SonarCloud
scan will start red on nearly every axis. Making a broad quality gate
blocking here would just fail every push until full remediation is
done elsewhere in the project.

The actual blocking decision belongs to the Security Gate stage
(issue #10), which is meant to aggregate findings across all scanning
stages (Gitleaks, Bandit, SonarCloud, Trivy, Checkov, ZAP) and apply a
single explicit policy: block on CRITICAL, warn on HIGH. Wiring
SonarCloud's own gate to fail the build here would duplicate and
potentially conflict with that centralized decision.

## Known Limitations
- Bandit only understands Python; it has no visibility into the
  Terraform/Kubernetes misconfigurations (those are IaC scanning,
  issue #6) or container-level issues (issue #5).
- SAST cannot catch business-logic flaws that don't look wrong in
  isolated code, e.g. TV-03 (no `amount > 0` check) and TV-05 (balance
  overflow) are logic errors a static scanner is unlikely to flag; a
  human code reviewer or DAST (issue #9) is the compensating control
  for that class of finding.
- False positives are expected on a first run of either tool against
  this codebase. Triage findings against `VULNERABILITIES.md` rather
  than assuming everything Bandit/SonarCloud reports maps to a tracked
  ID; some will be code-quality noise unrelated to the security case
  study.