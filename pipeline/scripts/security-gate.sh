#!/usr/bin/env bash
# security-gate.sh
#
# Aggregates the results of this project's scanning workflows for a given
# commit and makes a single block/warn decision, matching the pipeline
# diagram's Security Gate stage (block on CRITICAL, warn on HIGH).
#
# Design note: "blocking" here means the corresponding GitHub Actions
# workflow failed as a whole (Bandit, Checkov, Gitleaks etc. already exit
# non-zero on real findings). This is workflow-level granularity, not
# true per-finding severity parsing from each tool's report — see
# docs/ci-cd/security-gate.md for the tradeoff and how to extend this.
#
# Required environment variables:
#   GH_TOKEN  - a token with 'actions: read' access (GITHUB_TOKEN in CI)
#   REPO      - "owner/repo"
#   SHA       - the commit SHA to evaluate
#
# Exit code: 0 if the gate passes, 1 if any blocking workflow failed.

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${REPO:?REPO is required}"
: "${SHA:?SHA is required}"

BLOCKING_WORKFLOWS=(
  "Secret Scanning (Gitleaks)"
  "Static Analysis (SAST)"
  "Container Scanning"
  "IaC Scanning"
)

WARN_WORKFLOWS=(
  "DAST (OWASP ZAP)"
)

gate_failed=0
summary_file="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

{
  echo "## Security Gate Summary"
  echo ""
  echo "Evaluating commit: \`$SHA\`"
  echo ""
  echo "| Workflow | Type | Conclusion |"
  echo "|---|---|---|"
} >> "$summary_file"

check_workflow() {
  local name="$1"
  local kind="$2"

  conclusion=$(gh api \
    "repos/$REPO/actions/runs?head_sha=$SHA&per_page=50" \
    --jq ".workflow_runs[] | select(.name == \"$name\") | .conclusion" \
    | head -n1)

  if [ -z "$conclusion" ]; then
    conclusion="not run"
  fi

  echo "| $name | $kind | $conclusion |" >> "$summary_file"
  echo "$name -> $conclusion"

  if [ "$kind" = "BLOCKING" ] && [ "$conclusion" = "failure" ]; then
    gate_failed=1
  fi
}

for wf in "${BLOCKING_WORKFLOWS[@]}"; do
  check_workflow "$wf" "BLOCKING"
done

for wf in "${WARN_WORKFLOWS[@]}"; do
  check_workflow "$wf" "WARN"
done

echo "" >> "$summary_file"

if [ "$gate_failed" = "1" ]; then
  echo "**Result: BLOCKED** one or more blocking scans failed." >> "$summary_file"
  echo "Security gate BLOCKED: a blocking scan (Gitleaks, SAST, Container, or IaC) failed."
  exit 1
else
  echo "**Result: PASSED** no blocking scans failed. Check WARN rows above for non-blocking findings." >> "$summary_file"
  echo "Security gate PASSED."
fi