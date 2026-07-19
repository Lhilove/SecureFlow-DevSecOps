# CI/CD — Deploy to Local Kubernetes (kind)

## Why Not EKS
This stage was originally scoped as "Deploy to EKS." The project brief's
Safety Notes are explicit: **do not `terraform apply` the infrastructure
module against a real AWS account.** The Terraform in `infra/terraform`
is deliberately vulnerable (public EKS endpoint, AdministratorAccess IAM
role, publicly accessible RDS) Checkov is supposed to catch
these before they ever reach AWS, not after. Applying it for real would
mean actually standing up an internet-exposed, over-privileged EKS
cluster, exactly the outcome the whole pipeline exists to prevent.

The brief's actual instruction is to deploy to an isolated, local
Kubernetes cluster instead: kind, k3s, or minikube. This project uses
**kind** (Kubernetes IN Docker).

## Why kind
kind runs an entire Kubernetes cluster as Docker containers, no VM, no
nested virtualization, no cloud account. That has one big advantage over
k3s or minikube for this project specifically: **it runs inside GitHub
Actions itself.** GitHub-hosted runners already have Docker available,
so a real (if small) Kubernetes cluster can be created, used, and torn
down entirely within a CI job, the same pattern already used for DAST's
`docker compose` stack.

## Where It Runs
`.github/workflows/deploy.yml` triggers on:
- `push` to `main` and any `feature/**` branch
- `pull_request` targeting `main`

Steps, in order:
1. **Build Service Images** builds all three services, tagged to
   match exactly what the Kubernetes manifests reference
   (`secureflow/auth-service:latest`, etc.)
2. **Create kind Cluster** via `helm/kind-action`
3. **Load Images into kind** `kind load docker-image` explicitly
   copies each built image into the cluster. This step is easy to miss
   and easy to forget: a kind cluster cannot see images sitting in the
   runner's local Docker daemon by default, and since these images
   don't exist on Docker Hub, without this step every pod would sit in
   `ImagePullBackOff` indefinitely.
4. **Deploy Manifests (Kustomize)** `kubectl apply -k infra/kubernetes/base`,
   applied exactly as-is, deliberately unhardened
5. **Wait for Deployments** `kubectl wait --for=condition=available`
   against all five Deployments, a real readiness check rather than
   trusting `kubectl apply`'s exit code alone
6. **Show Cluster State** (`if: always()`) pods, services, and events,
   for visibility regardless of outcome
7. **Dump Pod Logs** (`if: failure()`) full logs from every pod if
   anything didn't come up cleanly
8. **Smoke Test Frontend** port-forwards to the frontend Service and
   curls it, confirming the application is actually reachable end to
   end, not just that Kubernetes reports the Deployment as "Available"

## Deploying the Deliberately Broken Baseline, on Purpose
This stage applies `infra/kubernetes/base` unmodified. Per the brief,
"the `base/` here is the broken version," hardening it is explicitly
scoped to a later stage (issue #15, Kustomize overlays), not this one.

This means it's entirely possible, maybe likely, for this stage to
surface real scheduling or runtime problems given what's already
planted in the manifests:
- CK-02 (root user, `runAsUser: 0`) and CK-04 (privileged containers,
  `allowPrivilegeEscalation: true`) may be rejected outright depending
  on the cluster's default Pod Security Standards
- CK-05 (no resource requests/limits) could cause unpredictable
  scheduling behavior under contention
- CK-03/CK-06 (`postgres:14`/`:latest`, no digest pinning) means the
  exact image pulled can drift between runs

If this stage fails to reach "Available" for a Deployment, that's not
necessarily a workflow bug, check whether it's actually one of the
planted CK findings blocking scheduling itself, that's useful evidence
for the technical article, not just noise to debug away.

## A Real Interaction Between a Kubernetes Default and a Planted Issue
This stage surfaced a genuine, confirmed failure worth documenting on
its own: none of the manifests set `imagePullPolicy` explicitly, and
Kubernetes defaults to `imagePullPolicy: Always` for any image tagged
`:latest`. Since `secureflow/auth-service`, `secureflow/frontend`, and
`secureflow/transaction-service` only exist as images already loaded
locally into the kind cluster (not on any real registry), that default
caused every pod to ignore the loaded image and instead attempt, and
fail, a real pull from Docker Hub: `pull access denied, repository
does not exist`.

This traces directly back to a real Checkov finding from IaC Scanning:
`CKV_K8S_15 "Image Pull Policy should be Always"` and the `:latest`
tag issue (CK-06). The planted misconfiguration didn't just fail a
scanner, it caused a genuine functional deployment failure once a real
cluster was involved.

**Fix applied in this workflow only, not the committed manifests:**
after `kubectl apply`, a patch step (`kubectl patch deployment ...
imagePullPolicy: IfNotPresent`) is applied to the three custom-image
Deployments. This makes local deployment work without editing
`infra/kubernetes/base`, which needs to stay in its deliberately
broken state for Checkov and the future hardened-overlays stage.

The patch triggers a normal Kubernetes rolling update: a new
ReplicaSet is created with the patched policy while the old one (still
defaulting to `Always`) scales down. Watching the event log during this
transition, the old pods failing with `ImagePullBackOff` and the new
pods succeeding with `"already present on machine"`, is a clean, real
demonstration of the fix actually working, not just theoretically
correct.


This stage exists to prove the pipeline can reach a real, running
cluster at all, nothing more. Everything that makes the cluster
actually secure comes after it:
- **OPA Gatekeeper** needs this cluster to exist before it
  can enforce anything against it
- **NetworkPolicies** needs running pods to segment
- **Vault** needs running services to inject secrets into
- **Falco** needs live workloads to generate runtime events

## Known Limitations
- This is a single-node, ephemeral cluster that exists only for the
  duration of the CI job. It proves the manifests are deployable, not
  that they'd behave identically on a real multi-node cluster.
- No persistent storage beyond the job's lifetime; `postgres` data is
  gone the moment the runner tears down. Fine for this stage's purpose
  (prove deployability), not representative of a real environment.
- The smoke test only confirms the frontend responds to a basic HTTP
  request. It doesn't exercise login, transactions, or any of the
  planted application vulnerabilities, that's DAST's job (issue #9),
  already covered separately.