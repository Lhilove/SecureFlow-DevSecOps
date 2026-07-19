# CI/CD — Kubernetes NetworkPolicies

## What This Fixes
IV-07: no network segmentation. Without any NetworkPolicy, every pod in
a Kubernetes namespace can reach every other pod, on any port, by
default. That means if any single service is compromised, say, through
one of the application vulnerabilities already catalogued in
`VULNERABILITIES.md`, the attacker doesn't just have that one service;
they have a clear network path to every database and every other
service in the namespace too. NetworkPolicies restrict that blast
radius to only the connections the application actually needs.

## The Pattern: Default-Deny, Then Explicit Allow
`00-default-deny.yaml` sets `podSelector: {}` (matches every pod) with
both `Ingress` and `Egress` in `policyTypes`, but no actual `ingress`
or `egress` rules. In Kubernetes NetworkPolicy semantics, that means
"block everything for every pod, unless some other policy explicitly
allows it." Every other file in this directory is one specific,
named exception carved out of that baseline.

This is the allow-list model, deny by default, permit only what's
proven necessary, rather than a deny-list (trying to enumerate every
bad connection, which is never complete).

## The Real Traffic Map
Confirmed directly from the application code (`app.py` in each
service), not assumed from the architecture diagram alone:

```
external → frontend (NodePort, port 5000)
frontend → auth-service (5001)       [login, register]
frontend → transaction-service (5002) [dashboard, transfer]
transaction-service → auth-service (5001) [JWT verification via /verify]
auth-service → auth-db (5432)
transaction-service → transaction-db (5432)
```

The `transaction-service → auth-service` path is easy to miss if you
only look at the high-level architecture: it's not part of the
frontend-facing flow, it's transaction-service calling *back* into
auth-service server-side to verify a token. Missing this in the policy
would silently break real functionality, transactions would fail with
no obviously-related NetworkPolicy error message pointing at the cause.

Every connection not in that list is denied, including
database-to-database traffic and any direct frontend-to-database path.

## DNS: The Easy Thing to Forget
`01-allow-dns.yaml` allows egress to UDP/TCP port 53 for every pod.
Without this, `default-deny-all` blocks DNS resolution too, which means
a pod can't even resolve the Service name `auth-service` to an IP
before any of the "correct" allow rules get a chance to matter. This is
a very common first mistake when implementing NetworkPolicies: policies
look correct on paper but everything breaks anyway, because DNS itself
got silently denied along with everything else.

## Critical Requirement: kind Needs Calico, Not Its Default CNI
kind's default networking plugin, `kindnet`, **does not implement
NetworkPolicy enforcement at all**. Applying every policy in this
directory against a stock kind cluster would succeed with no errors
and enforce absolutely nothing, a false-positive result that would be
easy to miss without specifically knowing to check for it.

`infra/kubernetes/network-policies/kind-no-cni-config.yaml` disables
kindnet at cluster creation (`disableDefaultCNI: true`), and the
workflow installs [Calico](https://www.tigera.io/project-calico/)
instead, a CNI that does enforce NetworkPolicy, before deploying
anything. This is the single most important detail in this stage;
skipping it produces a pipeline that looks green for entirely the
wrong reason.

## How the Workflow Verifies Real Enforcement
`.github/workflows/network-policies.yml` doesn't just apply the
policies and check for a clean `kubectl apply` exit code, that would
only prove the YAML is syntactically valid, not that anything is
actually being enforced. Instead, it spins up temporary `busybox` test
pods, labeled to match the same `svc:` labels the real services use,
and attempts real connections:

| Test | Pod label | Target | Expected |
|---|---|---|---|
| 1 | `svc=frontend` | `auth-service:5001` | **Allowed** |
| 2 | `svc=auth-service` | `transaction-db:5432` | **Blocked** |
| 3 | `svc=frontend` | `auth-db:5432` | **Blocked** |
| 4 | *(no label)* | `auth-service:5001` | **Blocked** |

Test 4 matters specifically: it confirms the default-deny baseline
itself is doing something, independent of any of the specific allow
rules, an unlabeled pod matches no allow rule at all, so it should be
blocked from everything.

## Known Limitations
- These policies operate on Kubernetes `Pod` labels and are namespace-
  scoped. They don't address traffic within a single pod, or anything
  happening before traffic reaches the CNI layer.
- Calico is used here specifically because it's needed for the kind/CI
  test to mean anything. A real target cluster (e.g. actual EKS) has
  its own CNI story, EKS supports Calico as an add-on, but this isn't
  automatic; deploying these same policies against a different cluster
  requires confirming that cluster's CNI also enforces NetworkPolicy.
- No egress restriction to the public internet is modeled here beyond
  what's implied by the allow-list (nothing explicitly allows internet
  egress, so it's denied by the default-deny baseline). Worth
  confirming this doesn't break anything if a service ever needs a
  genuine external dependency (none currently do).