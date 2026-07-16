# CI/CD — SBOM Generation

## What Is an SBOM
A Software Bill of Materials (SBOM) is a structured inventory of every
component that makes up a piece of software: application code, every
direct and transitive dependency, and (for a container image) the
underlying OS packages too. Think of it as a nutrition label for
software: instead of "flour, sugar, eggs," it lists "Flask 2.2.2,
PyJWT 2.4.0, openssl 3.0.2," and so on, down through every layer.

## Why This Stage Exists
Scanning tools like Trivy (issue #5) already build this same component
inventory internally in order to check it against CVE databases, but
they discard it once the scan finishes. An SBOM makes that inventory a
durable, standalone artifact.

That matters because vulnerability databases are not static. A
library that's clean today can have a CVE disclosed against it next
month. Without a stored SBOM, answering "are we affected by the new
CVE-2026-XXXXX in library Y?" means re-scanning every image you've
ever built. With a stored SBOM, it means grepping a file.

SBOMs are also increasingly a compliance requirement (e.g. US
Executive Order 14028 for federal software suppliers) and a
prerequisite for supply-chain transparency, you can't reason about
what's in your software if you don't have a list of what's in it.

## Tool: Syft (via anchore/sbom-action)
[Syft](https://github.com/anchore/syft) is Anchore's open-source SBOM
generator. It scans container images (and filesystems, directories,
archives) entirely offline, no external API calls, and detects
packages across OS package managers (apt, apk, rpm) and language
ecosystems (pip, npm, Go modules, and more), which covers both the
`python:3.9-slim` base layer and the `pip`-installed packages in each
service's `requirements.txt`.

The GitHub Actions integration, `anchore/sbom-action`, wraps Syft and
handles installation, execution, and artifact upload in one step.

## SBOM Formats: SPDX vs CycloneDX
Two competing standard formats exist:

| Format | Strengths |
|---|---|
| **SPDX** | Stronger licensing and provenance tracking; ISO-standardized (ISO/IEC 5962:2021) |
| **CycloneDX** | Built with vulnerability management and CI/CD workflows in mind |

This project generates **SPDX JSON** (`format: spdx-json`), matching
the format named in the project's architecture diagram. Either format
is defensible; the choice matters less than consistently picking one
and generating it every build.

## Where It Runs
`.github/workflows/sbom-generation.yml` triggers on:
- `push` to `main` and any `feature/**` branch
- `pull_request` targeting `main`

A matrix strategy builds and scans each service (`auth-service`,
`transaction-service`, `frontend`) independently, `fail-fast: false` so
one service's build failure doesn't block SBOM generation for the
others.

Each job:
1. Builds the service's image
2. Runs Syft against that image via `anchore/sbom-action`
3. The action automatically uploads the resulting SPDX JSON as a
   workflow artifact, no separate upload step is needed

## Why This Stage Doesn't "Fail"
Unlike Bandit, Trivy, or Checkov, this stage has no pass/fail
condition of its own. An SBOM is an inventory, not a judgment; there's
nothing here to be red or green about. The judgment (does this image
contain anything dangerous) already happened in scanning; this stage
just records what's inside, regardless of outcome.

## Relationship to the Rest of the Pipeline
Per this project's architecture diagram, the intended pipeline order
is: scan (issues #2–#6) → **Security Gate** (block on CRITICAL, warn
on HIGH; issue #10) → Cosign image signing (issue #8) → SBOM
generation → push to registry. In other words, by the time an SBOM is
generated and an image is signed, that image should have already
cleared the security gate. This project currently builds these stages
independently and out of that strict order (SBOM before the gate
exists yet), which is fine for incrementally building and testing each
piece, but worth reconciling into the correct sequence once issue #10
(Security Gate) exists, so the final assembled pipeline only signs and
publishes SBOMs for images that actually passed.

## Known Limitations
- An SBOM lists what's in an image; it doesn't itself catch anything
  dangerous. It needs to be paired with scanning (already covered)
  and, for real value over time, some process for periodically
  re-checking stored SBOMs against updated CVE databases.
- SBOM accuracy depends on Syft's detectors recognizing the package
  managers in use. Anything installed by unconventional means
  (manually copied binaries, custom scripts) may not appear in the
  inventory.
- Generating an SBOM per build (rather than only on release) produces
  a lot of artifacts over time; for a real production pipeline, a
  retention/storage policy (e.g. only persist SBOMs for tagged
  releases long-term) is worth considering.