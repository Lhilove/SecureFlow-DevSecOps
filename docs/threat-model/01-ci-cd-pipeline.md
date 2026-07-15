# Threat Model — CI/CD Pipeline

## System Overview
A secure CI/CD pipeline for a fintech microservices platform built on 
GitHub Actions, Amazon EKS, and supporting security tooling. The pipeline 
flow is: Developer git push → GitHub Actions → Gitleaks (secrets detection) 
→ SonarQube (SAST) → Trivy (container + IaC scan) → Checkov (IaC policy) 
→ Security Gate (block on CRITICAL, warn on HIGH) → OWASP ZAP (DAST) → 
Cosign (image signing) → SBOM generation → Amazon ECR → Deploy to EKS.

## Assets
- GitHub repository: source code and pipeline configuration
- GitHub Actions secrets: AWS credentials, Vault tokens, signing keys
- Amazon ECR: container registry holding production images
- Amazon EKS cluster: production Kubernetes environment
- HashiCorp Vault: secrets management for all microservices
- SonarQube: SAST scan results and quality gates
- Cosign signing keys: image integrity verification
- SBOM: software bill of materials for supply chain visibility



## Trust Boundaries
- Developer workstation → GitHub (trust boundary: GitHub authentication)
- GitHub Actions runner → AWS services (trust boundary: OIDC federation 
  or IAM role assumption)
- ECR → EKS (trust boundary: Cosign image verification + OPA Gatekeeper)
- EKS pods → HashiCorp Vault (trust boundary: Vault agent authentication)
- External internet → Pipeline (trust boundary: branch protection rules)

## STRIDE Analysis

### Spoofing
- A developer's credentials can be stolen through phishing due to 
  absence of MFA or weak password policy
- Attacker authenticates to GitHub as the legitimate developer and 
  pushes malicious code into the pipeline
- Pipeline trusts the commit as legitimate and builds and deploys 
  the backdoored image to production
- Dependency confusion attack: attacker publishes a malicious package 
  with the same name as an internal dependency to a public registry, 
  pipeline pulls the malicious version during build


### Tampering
- Attacker with repository access modifies GitHub Actions workflow 
  files to skip security scans or whitelist findings
- SonarQube quality gate results tampered with to allow vulnerable 
  code through the security gate
- Checkov IaC policies modified to permit misconfigured infrastructure
- Container image modified after signing but before deployment if 
  Cosign verification is not enforced at admission
- Malicious code injected through a compromised third-party dependency 
  pulled during the build process

### Repudiation
- Without proper audit logging, a malicious insider could push code, 
  trigger a deployment, or modify pipeline configuration and deny 
  involvement
- If GitHub Actions logs are not retained and tamper-evident, there 
  is no forensic trail to attribute pipeline actions to specific actors
- Mitigation: enforce signed commits, retain immutable audit logs, 
  enable GitHub audit log streaming to a SIEM

### Information Disclosure
- github actions can expose logs if they're accidentally printed during pipeline execution, github actions can leaks secrets through a compromised third-party action. 

### Denial of Service
- an attacker can flood the pipeline with PRs triggering scans and exhausting github actions, they take the SonarQube offline so the security gate would not function or corrupt the ECR registry making deployment fail.

### Elevation of Privilege
- Once the attacker gain access to the github they can access the Amazon Kubernetes (EKS) because github actions has access to AWS credentials to push to ECR, EKS service account tokens, Vault tokens for secrets, and the ability to deploy malicious images to production EKS.

## Attack Scenarios

### Scenario 1: Compromised Developer Account (Critical)
Attacker phishes a developer and steals credentials. No MFA is enforced.
Attacker pushes a branch with a backdoored dependency. Pipeline builds 
and deploys the malicious image to production EKS. Customer financial 
data is exfiltrated.
Impact: Critical; full production compromise, data breach, regulatory 
penalties under NDPR.

### Scenario 2: Malicious Third-Party GitHub Action (High)
A widely used GitHub Action is compromised by its maintainer or through 
a supply chain attack. The action exfiltrates AWS_ACCESS_KEY_ID and 
AWS_SECRET_ACCESS_KEY from the Actions environment. Attacker gains 
full AWS access ECR, EKS, RDS.
Impact: High; full infrastructure takeover.

### Scenario 3: Pipeline Denial of Service (Medium)
Attacker with repository access floods open PRs triggering expensive 
SonarQube and Trivy scans. GitHub Actions minutes exhausted. Legitimate 
hotfix deployments blocked during a production incident.
Impact: Medium; deployment delays, potential SLA breach for fintech 
platform.

## Mitigations

### Existing Controls
- Gitleaks prevents secrets being committed to the repository
- Security gate blocks deployments on CRITICAL findings
- Cosign ensures only signed images reach production
- OPA Gatekeeper enforces admission control policies on EKS

### Gaps and Recommendations
- Enforce MFA on all GitHub accounts with access to the repository
- Pin all third-party GitHub Actions to a specific commit SHA not a 
  tag; tags are mutable and can be hijacked
- Use GitHub OIDC federation instead of long-lived AWS credentials 
  in Actions secrets
- Enable branch protection rules; require PR reviews, no direct 
  pushes to main
- Retain GitHub audit logs and stream to observability stack 
  (already has Loki/Grafana)
- Implement signed commits to address repudiation risk
- Set GitHub Actions spending limits to prevent DoS via PR flooding