# CI/CD — OPA Gatekeeper (Admission Control)

## What This Stage Actually Does Differently
Every stage before this one is a scanner: it reads files, images, or
HTTP responses and reports on what it finds, after the fact. Gatekeeper
is not a scanner. It's an **admission controller**, a piece of software
that sits inside the Kubernetes API server's request pipeline itself
and gets a say in every single `kubectl apply` (or any create/update
request) before Kubernetes commits it to the cluster.

If a resource violates policy, Kubernetes never creates it, not even
briefly, not even long enough to fail health checks later. This is the
difference between "we found the bad guy after he got in" (everything
upstream) and "the door physically wouldn't open for him" (this stage).

## Why This Needs a Live Cluster, Unlike Every Prior Stage
SAST reads source. Trivy reads an image. Checkov reads YAML files
directly. None of them need Kubernetes running at all. Gatekeeper only
exists *as* a running component inside a cluster's control plane,
there's no "scan this file" equivalent; the only way to test it is to
actually try to create something and watch what the API server does.

## Core Concepts

### ConstraintTemplate
Defines a reusable *rule*, written in [Rego](https://www.openpolicyagent.org/docs/latest/policy-language/),
Open Policy Agent's purpose-built policy language. A ConstraintTemplate
on its own does nothing, it's a rule definition, not yet applied to
anything.

Example (simplified from `no-root-user.yaml`):
```rego
violation[{"msg": msg}] {
  c := input.review.object.spec.template.spec.containers[_]
  c.securityContext.runAsUser == 0
  msg := sprintf("Container '%v' must not run as UID 0 / root (CK-02)", [c.name])
}
```
Read this like a query, not a script: "for any container `c` in the
object being reviewed, if its `runAsUser` is `0`, produce a violation
with this message." Rego is declarative; it describes what a violation
looks like, not a sequence of steps.

### Constraint
An *instance* of a ConstraintTemplate, applied to specific resources.
The template defines the rule; the Constraint decides what it applies
to:
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sNoRootUser
metadata:
  name: no-root-user
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
    namespaces:
      - "secureflow"
```
Same template could be reused with a different Constraint to apply to
a different namespace, or a different resource kind, without touching
the Rego at all.

## The Four Policies Built Here
Each maps directly to a planted finding already confirmed by Checkov
(IaC Scanning) and, for pull failures, by the Local Kubernetes Deploy
stage:

| ConstraintTemplate | Blocks | Maps to |
|---|---|---|
| `K8sNoPrivilegedContainer` | `privileged: true`, `allowPrivilegeEscalation: true` | CK-04 |
| `K8sNoRootUser` | `runAsUser: 0` | CK-02 |
| `K8sNoLatestTag` | `:latest` tag or no tag at all | CK-06 |
| `K8sRequireResourceLimits` | missing CPU/memory limits | CK-05 |

## How the Workflow Proves This Actually Works
`.github/workflows/gatekeeper.yml`:
1. Creates a kind cluster
2. Installs Gatekeeper itself (the admission controller components)
3. Waits for Gatekeeper's own deployments to be ready
4. Applies all four ConstraintTemplates, then waits for their CRDs to
   be established (Gatekeeper dynamically creates a Kubernetes CRD per
   template; applying a Constraint before its CRD exists fails)
5. Applies all four Constraints, scoped to the `secureflow` namespace
6. Attempts to apply `infra/kubernetes/base`, the same deliberately
   broken manifests used in Local Kubernetes Deploy, **unmodified**
7. Checks the outcome with **inverted logic** from every other stage:
   the job fails if the apply *succeeds*. A successful apply here would
   mean Gatekeeper failed to enforce anything, which is the actual
   failure condition worth catching.

This inversion matters and is easy to get backwards: most CI checks
fail when something goes wrong. Here, the "something goes wrong" case
is Gatekeeper working correctly and blocking the deploy, that's the
expected, desired outcome, and it shows up as the `kubectl apply` step
itself failing (which is fine, `continue-on-error: true` is set on
that specific step so the workflow can inspect the outcome deliberately
rather than just dying there).

## Reading a Gatekeeper Denial
A real rejection looks like:
```
Error from server (Forbidden): error when creating "infra/kubernetes/base":
admission webhook "validation.gatekeeper.sh" denied the request:
[no-root-user] Container 'auth-service' must not run as UID 0 / root (CK-02)
[no-privileged-containers] Container 'frontend' must not run as privileged (CK-04)
```
Each line traces back to a specific Constraint's violation message,
this is Gatekeeper telling you exactly which rule, which resource, and
why, at the moment of attempted creation, not after the fact.

## Known Limitations
- **Enforcement only covers what's explicitly written as a Constraint.**
  Anything not modeled in Rego passes through untouched. This is four
  policies out of many possible ones; a real production Gatekeeper
  deployment typically uses a much larger policy library (see
  [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library)
  for a maintained set of common policies).
- **This stage tests enforcement against the broken baseline on
  purpose**, it does not deploy a working, compliant application. Once
  hardened Kustomize overlays exist, a useful follow-up test is
  confirming those overlays deploy *successfully* under these same
  Constraints, proving the fix actually satisfies the policy, not just
  that the policy exists.
- **`failurePolicy` defaults matter.** Gatekeeper's admission webhook
  can be configured to fail open (`Ignore`, allow requests through if
  the webhook itself is unreachable) or fail closed (`Fail`, reject
  requests if the webhook can't be reached). This project uses
  Gatekeeper's own installation defaults; explicitly setting this is
  worth revisiting for a production-representative setup.