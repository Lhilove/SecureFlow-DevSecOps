# CI/CD — Image Signing

## Purpose
Scanning (issues #2–#6) answers "does this image have known problems?"
Signing answers a different question: "did this exact image really
come from our pipeline, unmodified?" Without signing, anyone who can
push to a registry, or intercept/replace an image in transit, or
compromise a registry itself, can substitute a different image behind
the same tag, and nothing downstream would know the difference.

This is directly relevant to this project's own supply-chain story:
the `trivy-action` compromise documented in `docs/ci-cd/container.md`
is exactly the class of attack image signing is designed to make
detectable. A signed, verified image gives a strong guarantee about
provenance; an unsigned one only gives you a name and a tag, which can
be silently repointed.

## Tool: Cosign (Sigstore)
[Cosign](https://github.com/sigstore/cosign) is the signing tool from
the [Sigstore](https://www.sigstore.dev/) project. It supports two
signing modes:

- **Key-based**: a long-lived private key signs the image. The key
  must be generated, stored securely (ideally in a KMS/HSM), and
  rotated. If it leaks, every signature it ever produced is suspect.
- **Keyless (OIDC-based)**: no long-lived key at all. This project
  uses this mode.

## How Keyless Signing Actually Works
This is the part that seems like magic the first time, so worth
walking through step by step:

1. The GitHub Actions workflow requests an OIDC token from GitHub,
   proving "I am this exact workflow, in this exact repo, at this
   commit." This requires the `id-token: write` permission.
2. Cosign presents that token to **Fulcio**, a free public certificate
   authority run by the Sigstore project. Fulcio verifies the token
   and issues a short-lived certificate (valid for minutes) binding
   that identity to a freshly generated signing key.
3. Cosign signs the image with that key.
4. The signature, certificate, and a record of the whole transaction
   get written to **Rekor**, a public, append-only transparency log.
   Anyone can look up that entry later; it can't be edited or deleted.
5. The ephemeral private key is discarded immediately. There was
   never anything long-lived to steal.

Verification later works by checking: does a valid signature exist for
this exact image digest, and does the certificate on that signature
say it came from the expected repo and workflow? `cosign verify` with
`--certificate-identity` (or `--certificate-identity-regexp`) and
`--certificate-oidc-issuer` checks exactly that.

## Where It Runs
`.github/workflows/sign-image.yml` triggers on:
- `push` to `main` and any `feature/**` branch
- `pull_request` targeting `main`

A matrix strategy handles all three services independently. Each job:
1. Logs into GitHub Container Registry (GHCR) using `GITHUB_TOKEN`, no
   separate registry secret needed
2. Builds and pushes the image, tagged with the commit SHA (never
   `latest` — signing a mutable tag doesn't mean anything, since the
   tag could point somewhere else five minutes later; signing targets
   the immutable digest)
3. Installs Cosign
4. Signs the pushed image by digest
5. Verifies the signature, proving the whole chain actually worked

## Why GHCR Instead of Amazon ECR
This project's architecture diagram shows signing happening just
before a push to Amazon ECR. That's the intended production target,
but this repo doesn't yet have AWS credentials wired into CI (no ECR
login step, no IAM role). GHCR authenticates with the same
`GITHUB_TOKEN` already used elsewhere in this pipeline, so it's the
simplest way to validate the signing mechanism itself works, without
that being blocked on unrelated cloud credential setup. Swapping the
registry target to ECR later is a login-step change, not a
signing-logic change.

## Known Limitations
- Keyless signing depends on GitHub's OIDC provider, Fulcio, and Rekor
  all being available at signing time. If any of those services are
  down, signing fails; there's no automatic fallback to key-based
  signing configured here.
- Signing proves provenance (this image came from this pipeline). It
  does not itself prove the image is safe, that's still scanning's
  job. A signed image can still contain the CRITICAL findings from
  issues #3–#6; signing and scanning answer different questions and
  neither replaces the other.
- This stage signs the image. It doesn't yet enforce that signature at
  deploy time, nothing currently stops an unsigned image from being
  deployed to the EKS cluster. Enforcing "only run signed images"
  would require an admission controller policy (e.g. Sigstore's
  `policy-controller` or an OPA Gatekeeper constraint checking
  signatures), which is not yet a tracked issue in this project.