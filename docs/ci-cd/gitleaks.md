# CI/CD — Secret Scanning with Gitleaks

## Purpose
Gitleaks scans every push and pull request for hardcoded secrets before
they reach `main`. It targets IV-04 directly (secrets committed to the
repo, including `.env`, hardcoded DB passwords, JWT secrets, and AWS
keys) and acts as a compensating control for IV-01 and IV-03, which
originate from the same root cause: credentials living in source
control instead of a secrets manager.

This scan is a detective control, not a preventive one. It stops a
leak from merging into `main`; it does not stop a developer from
committing a secret locally. Section "Local / Pre-Commit Scanning"
below covers the preventive layer.

## Where It Runs
`.github/workflows/secrets-scan.yml` triggers on:
- `push` to `main` and any `feature/**` branch
- `pull_request` targeting `main`

`fetch-depth: 0` is required in the checkout step so Gitleaks can walk
full git history rather than just the current tip, since a secret
removed in a later commit is still exploitable if it exists anywhere
in history.

## Tool: gitleaks-action@v3
The workflow uses `gitleaks/gitleaks-action@v3`, a wrapper around the
Gitleaks binary. Configuration is passed through `env:`, not `with:`
this action does not expose `config` or `args` as step inputs, and
passing them there is silently ignored by GitHub Actions rather than
causing a workflow error, which makes the mistake easy to miss.

```yaml
- name: Run Gitleaks
  uses: gitleaks/gitleaks-action@v3
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    GITLEAKS_CONFIG: .gitleaks.toml
```

Relevant environment variables:

| Variable | Purpose |
|---|---|
| `GITHUB_TOKEN` | Lets the action comment on PRs when a leak is found |
| `GITLEAKS_CONFIG` | Path to the custom ruleset (`.gitleaks.toml`) |
| `GITLEAKS_ENABLE_UPLOAD_ARTIFACT` | Uploads a SARIF report on findings (default `true`) |
| `GITLEAKS_ENABLE_SUMMARY` | Writes a job summary (default `true`) |
| `GITLEAKS_LICENSE` | Required only for org-owned repos, not personal accounts |

The action fails the job (non-zero exit) automatically when a leak is
detected no manual report parsing or `if:` gating is required for
the pipeline to block a merge.

## Configuration: `.gitleaks.toml`
```toml
[extend]
useDefault = true

[allowlist]
paths = [
    '''docs/''',
    '''README\.md'''
]
```

- `useDefault = true` extends Gitleaks' built-in ruleset (AWS keys,
  GitHub/GitLab tokens, private keys, Slack tokens, generic
  high-entropy secrets, and more) rather than replacing it.
- The allowlist excludes only `docs/` and `README.md` by path, since
  those directories intentionally reference example secret formats
  for documentation purposes. `.env` and application source are
  deliberately **not** excluded this repo's `.env` is IV-04 and is
  supposed to trip the scan.

## What It Catches Here
Format-specific rules (AWS access key regex, etc.) match regardless of
how "realistic" the value looks, so the AWS example keys in `.env`
still trigger `aws-access-token` and `aws-secret-key` findings even
though they're AWS's own published placeholder values.

Low-entropy plaintext strings like `authpassword`, `txnpassword`, and
`supersecretjwtkey` are a different case: Gitleaks' generic-secret
rules combine a proximity keyword (`password`, `secret`, `key`, etc.)
with a Shannon entropy threshold, and short dictionary-like strings
can fall under that threshold and go undetected. This is a known gap,
not a bug — it's the reason entropy-only scanning is treated as one
layer of defense rather than the whole control, and why remediation
work (Vault/Secrets Manager migration, credential rotation) doesn't
wait on Gitleaks to flag every weak value in `.env`.

## Verifying the Control Works
1. Confirm `.env` is committed and pushed on the branch being scanned
   (`git log --all -- .env`).
2. Open the Actions run for that exact commit SHA and check the
   Gitleaks step logs directly, not just the overall job status.
3. A passing (green) run on a branch containing `.env` as committed
   here indicates a misconfiguration, not a clean repo — treat it as
   a signal to re-check the workflow's `env:` block and the action
   version in use.

## Remediation Path When a Real Secret Leaks
1. Rotate/revoke the credential at the source (AWS IAM, database,
   JWT signing key) assume it is compromised the moment it's
   pushed, even to a private repo.
2. Remove it from the current commit.
3. Purge it from git history (`git filter-repo` or BFG Repo-Cleaner),
   since `fetch-depth: 0` scanning means Gitleaks and anyone with
   clone access can still see it in prior commits otherwise.
4. Re-run the workflow to confirm a clean scan before merging.

## Local / Pre-Commit Scanning
CI catches a leak after push; a pre-commit hook catches it before it
ever leaves the developer's machine. Recommended for a 4-person team
sharing this repo:

```bash
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks
```

This runs the same `.gitleaks.toml` ruleset locally via
[pre-commit](https://pre-commit.com/), so findings are consistent
between a developer's machine and CI.

## Known Limitations
- Entropy-based detection can miss short, low-entropy secrets (see
  above) — this scanner is one layer, not a substitute for not
  committing secrets in the first place.
- Full-history scanning on every push/PR is thorough but adds runtime
  as the repo grows; if this becomes a bottleneck, consider scoping
  PR runs to the diff and reserving full-history scans for a
  scheduled nightly job instead.
- Gitleaks detects secrets already in the repo. It does not prevent
  secrets sprawl in running containers, environment variables at
  runtime, or logs — those are covered by the Vault/Secrets Manager
  work elsewhere in this project, not by this control.