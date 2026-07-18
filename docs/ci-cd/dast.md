# CI/CD — DAST (OWASP ZAP)

## Purpose
Dynamic Application Security Testing (DAST) attacks the application
while it's actually running, sending real HTTP requests and inspecting
real responses, rather than reading source code. This is fundamentally
different from every scanning stage so far:

| Stage | Looks at |
|---|---|
| SAST | Source code, without running it |
| Dependency scan | Declared package versions |
| Container scan | Built image contents |
| IaC scan | Infrastructure definitions |
| **DAST (this stage)** | **The live, running application** |

This stage targets findings SAST structurally cannot see: reflected
behavior in actual HTTP responses (FV-01, FV-02 — XSS), missing
security headers, cookie flags, and anything that only manifests once
requests, responses, sessions, and routing are all actually in play.

## Tool: OWASP ZAP (Baseline Scan)
[OWASP ZAP](https://www.zaproxy.org/) (Zed Attack Proxy) is the
standard open-source DAST tool, already named in this project's
architecture diagram. This stage runs ZAP's **baseline scan** via
`zaproxy/action-baseline`, not a full active scan.

### Baseline vs Full Scan
- **Baseline**: passively crawls the application (following links,
  submitting forms with the default browsing behavior) and inspects
  what comes back, headers, cookies, response content, without
  deliberately trying to break anything. Fast, safe to run on every
  push.
- **Full scan**: actively attacks input fields, tries injection
  payloads, fuzzes parameters. Slower, and more likely to actually
  trigger the vulnerable behavior it's looking for (e.g. really
  triggering FV-01/FV-02 XSS), but riskier to run unattended against
  an app with real state (like this one's databases).

This stage starts with baseline as the safer default. Upgrading to a
full scan (`docker_name` pointed at ZAP's full-scan image, or adding
`-j` active scan options via `cmd_options`) is a reasonable next step
once baseline results are reviewed and understood.

## Why This Stage Needs a Running App
Unlike every other scanning stage, DAST has nothing to look at until
something is actually listening on a port. This workflow:

1. Runs `docker compose up -d --build`, standing up all five
   containers (both Postgres databases, all three Flask services)
   inside the CI runner itself
2. Polls `http://localhost:5000` (the frontend) until it responds,
   rather than assuming a fixed startup delay, since container
   startup time can vary between runs
3. Only then points ZAP at the running frontend
4. Tears the whole stack down afterward (`docker compose down -v`,
   `if: always()`) regardless of scan outcome, so the runner doesn't
   leave containers or volumes behind

The frontend (port 5000) is the scan target because it's the actual
user-facing entry point, the same thing a real external attacker would
reach first, rather than scanning the backend services directly.

## What This Should Catch
Given the planted findings in `VULNERABILITIES.md`:
- **FV-01, FV-02** (reflected/stored XSS) — ZAP's passive scanning can
  flag suspicious reflected input even without deliberately exploiting
  it; a full active scan would more reliably trigger and confirm these
- Missing or weak security headers (`X-Content-Type-Options`,
  `Content-Security-Policy`, `Strict-Transport-Security`, etc.), a
  category baseline scanning catches well and this project hasn't
  explicitly catalogued yet
- Cookie security flags, relevant given the `SESSION_SECRET: changeme`
  planted issue (FV-03) in `docker-compose.yml`

Treat actual ZAP output as authoritative over this list.

## Why `fail_action: false`
Consistent with every other stage in this pipeline, this stage reports
findings without failing the build. This is deliberate scaffolding,
not a gap: the intent is to get every scanning stage producing real,
visible findings first, then wire enforcement into a single Security
Gate stage (issue #10) that aggregates across all of them, rather than
each stage independently deciding what's blocking.

## Known Limitations
- **Unauthenticated scanning only.** ZAP is scanning as an anonymous
  visitor, it never logs in. Anything behind authentication (most of
  the transaction service's functionality, IDOR/mass-assignment
  findings like TV-01/TV-02) is invisible to this scan as configured.
  Authenticated scanning (scripting a login flow first) is a
  meaningful next step, not yet built here.
- Baseline scanning is passive; it's likely to under-report compared
  to a full active scan, some findings may exist but not surface until
  ZAP actually tries to exploit them.
- The scan runs against a freshly built, freshly seeded local stack
  every time, so results should be consistent, but any given run's
  findings depend on ZAP's own ruleset at that point in time, which
  updates independently of this project.
- Running the full app stack inside CI adds meaningful time and
  resource usage compared to every prior stage; if this becomes a
  bottleneck, consider running DAST only on PRs to `main` rather than
  every push to a feature branch.