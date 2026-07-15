# Threat Model — Software Supply Chain Security

## System Overview

The SecureFlow software supply chain encompasses the entire lifecycle of application code, dependencies, build artifacts, container images, and deployment manifests from development through production.

Developers commit code to GitHub, triggering GitHub Actions workflows that execute security controls including Gitleaks, SonarQube, Trivy, Checkov, OWASP ZAP, Cosign image signing, and SBOM generation. Successfully validated container images are stored in Amazon ECR before deployment to Amazon EKS.

The objective of the supply chain is to ensure that only trusted, verified, and secure software artifacts reach production.

---

## Assets

- Source Code Repository
- Git Commit History
- GitHub Actions Workflows
- Third-Party Dependencies
- Open Source Packages
- Container Images
- Dockerfiles
- Infrastructure as Code (Terraform)
- Kubernetes Manifests
- Build Artifacts
- Software Bill of Materials (SBOM)
- Cosign Signatures
- Amazon ECR Repository
- Build Provenance Metadata

---

## Trust Boundaries

- Developer Workstation → GitHub Repository
- GitHub Repository → GitHub Actions
- GitHub Actions → Dependency Registries
- GitHub Actions → Security Scanners
- GitHub Actions → Amazon ECR
- Amazon ECR → Amazon EKS
- Third-Party Dependencies → Build Process

---

## STRIDE Analysis

### Spoofing

- Attacker impersonates a trusted package publisher.
- Compromised GitHub account pushes malicious commits.
- Fake container registry serves malicious images.
- Build system accepts unsigned artifacts.

### Tampering

- Malicious dependency injected into the build.
- GitHub Actions workflow modified to bypass security controls.
- Container image altered before deployment.
- SBOM modified to hide vulnerable components.
- Infrastructure manifests changed before deployment.

### Repudiation

- Developer denies introducing malicious code.
- Workflow changes occur without audit logs.
- Missing commit signatures prevent attribution.
- Build provenance cannot be verified.

### Information Disclosure

- Build logs expose secrets.
- SBOM reveals sensitive internal components.
- Container images include confidential files.
- Source code leaked through public repositories.
- Secrets committed into version control.

### Denial of Service

- Dependency registry outage prevents builds.
- CI/CD runners exhausted by excessive workflow executions.
- Large dependency graphs significantly slow builds.
- Artifact registry becomes unavailable.
- Security scanners fail, blocking deployments.

### Elevation of Privilege

- Malicious GitHub Action gains access to repository secrets.
- Compromised dependency executes arbitrary code during build.
- Build runner escapes into the host environment.
- Excessive CI permissions allow unauthorized deployments.
- Attackers obtain signing keys and sign malicious images.

---

## Attack Scenarios

### Scenario 1: Dependency Confusion Attack (Critical)

An attacker publishes a malicious package with the same name as an internal dependency to a public package registry. During the build process, the package manager downloads the malicious dependency instead of the intended internal package. The malicious code executes within the CI environment and steals repository secrets and cloud credentials.

Impact: Critical; CI compromise, credential theft, malicious code execution, and supply chain compromise.

---

### Scenario 2: Compromised GitHub Action (Critical)

A third-party GitHub Action used within the pipeline is compromised by its maintainer or through a supply chain attack. During workflow execution, the action exfiltrates GitHub secrets, AWS credentials, and signing keys before allowing the build to continue successfully.

Impact: Critical; complete CI/CD compromise and unauthorized production deployments.

---

### Scenario 3: Unsigned Container Deployment (High)

Image signature verification is disabled or incorrectly configured. An attacker uploads a malicious container image to Amazon ECR using compromised credentials. The Kubernetes cluster deploys the image without verifying its authenticity.

Impact: High; execution of untrusted workloads within the production environment.

---

## Mitigations

### Existing Controls

- Gitleaks detects committed secrets.
- SonarQube performs static application security testing.
- Trivy scans container images and Infrastructure as Code.
- Checkov validates Infrastructure as Code against security policies.
- OWASP ZAP performs dynamic application security testing.
- Cosign signs production container images.
- SBOM generation provides software component visibility.
- Security Gates prevent deployment of critical vulnerabilities.

### Gaps and Recommendations

- Pin all GitHub Actions to immutable commit SHAs.
- Use GitHub OIDC instead of long-lived cloud credentials.
- Verify container signatures before deployment.
- Continuously monitor dependencies for newly disclosed vulnerabilities.
- Enforce signed commits for all contributors.
- Adopt the principle of least privilege for CI/CD permissions.
- Store signing keys within a hardware-backed key management system.
- Regularly review and update SBOMs.
- Verify build provenance before deployment.
- Continuously audit third-party dependencies for trustworthiness.