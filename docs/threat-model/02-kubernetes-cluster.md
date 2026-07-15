# Threat Model — Kubernetes Cluster

## System Overview

The Kubernetes cluster hosts the SecureFlow fintech microservices on Amazon EKS. It contains the Frontend/BFF, Authentication Service, Transaction Service, PostgreSQL database, and supporting security components including OPA Gatekeeper, HashiCorp Vault, Falco, and Kubernetes Network Policies.

Amazon EKS provides the managed Kubernetes control plane while worker nodes execute application workloads. Container images are built through the CI/CD pipeline, signed with Cosign, stored in Amazon ECR, and deployed into the cluster after passing security gates.

The cluster is responsible for workload isolation, admission control, runtime threat detection, secrets management, and network segmentation.

---

## Assets

- Amazon EKS Control Plane
- Kubernetes API Server
- Worker Nodes
- Kubernetes etcd
- Kubernetes RBAC Roles and Service Accounts
- Frontend/BFF Pods
- Authentication Service Pods
- Transaction Service Pods
- PostgreSQL Database
- HashiCorp Vault
- OPA Gatekeeper
- Falco Runtime Detection
- Kubernetes Secrets
- Network Policies
- Container Images
- Persistent Volumes

---

## Trust Boundaries

- Amazon ECR → Amazon EKS Admission Controller
- Internet → Kubernetes Ingress Controller
- Ingress Controller → Frontend/BFF
- Frontend/BFF → Authentication Service
- Authentication Service → Transaction Service
- Application Services → PostgreSQL
- Pods → HashiCorp Vault
- Pods → Kubernetes API Server
- Worker Nodes → Kubernetes Control Plane

---

## STRIDE Analysis

### Spoofing

- Attacker steals a Kubernetes Service Account token and impersonates a legitimate workload.
- Compromised pod authenticates to Vault using a stolen Kubernetes identity.
- Rogue container impersonates another internal microservice because service identity verification is absent.

### Tampering

- Kubernetes manifests modified to deploy privileged containers.
- ConfigMaps altered to change application behavior.
- RBAC permissions modified to grant cluster-admin privileges.
- Admission policies disabled or bypassed.
- Unsigned container images deployed if signature verification is not enforced.

### Repudiation

- Cluster administrator modifies resources without audit logging.
- RBAC changes cannot be attributed to a specific user.
- Pod exec sessions are not logged.
- Kubernetes audit logs are disabled, preventing forensic investigations.

### Information Disclosure

- Kubernetes Secrets exposed through compromised workloads.
- Service Account tokens stolen from mounted volumes.
- Vault tokens leaked through application logs.
- Misconfigured RBAC allows reading Secrets.
- PostgreSQL credentials exposed through ConfigMaps.
- Public dashboards expose cluster information.

### Denial of Service

- Attacker creates excessive Pods exhausting cluster resources.
- CPU and memory exhaustion due to missing resource limits.
- Kubernetes API flooded with requests.
- Persistent Volumes filled causing database outage.
- Malicious deployments trigger continuous CrashLoopBackOff events.
- etcd storage exhaustion impacts cluster availability.

### Elevation of Privilege

- Privileged containers escape to the host.
- Overly permissive RBAC grants cluster-admin access.
- HostPath volumes expose the node filesystem.
- Container runtime escape vulnerabilities compromise worker nodes.
- Service Account tokens abused to perform privileged API operations.

---

## Attack Scenarios

### Scenario 1: Compromised Microservice Pod (Critical)

An attacker exploits a Remote Code Execution (RCE) vulnerability in the Transaction Service. The compromised pod accesses its Service Account token and communicates with the Kubernetes API. Because RBAC permissions are overly permissive, the attacker creates privileged workloads and gains cluster-wide control.

Impact: Critical; full cluster compromise, database theft, secrets disclosure, and production outage.

---

### Scenario 2: Secret Theft Through Vault (High)

A compromised workload authenticates to HashiCorp Vault using its Kubernetes identity. Due to overly permissive Vault policies, the attacker retrieves database credentials, JWT signing keys, and application secrets beyond its intended scope.

Impact: High; credential compromise, lateral movement, and unauthorized access to sensitive services.

---

### Scenario 3: Lateral Movement Between Pods (High)

An attacker compromises the Frontend/BFF through an application vulnerability. Network Policies are missing or overly permissive, allowing unrestricted communication with the Authentication Service, Transaction Service, and PostgreSQL database.

Impact: High; complete application compromise, financial data theft, and service disruption.

---

## Mitigations

### Existing Controls

- OPA Gatekeeper enforces Kubernetes admission policies.
- HashiCorp Vault manages application secrets.
- Falco detects suspicious runtime behavior.
- Network Policies implement default-deny communication.
- Cosign ensures only signed images are deployed.
- CI/CD Security Gate blocks vulnerable container images before deployment.

### Gaps and Recommendations

- Enforce Kubernetes Pod Security Standards (Restricted profile).
- Apply least-privilege RBAC for all Service Accounts.
- Disable automatic mounting of Service Account tokens where unnecessary.
- Require image signature verification at admission.
- Enable Kubernetes audit logging.
- Rotate Service Account tokens regularly.
- Encrypt Kubernetes Secrets at rest.
- Enforce namespace isolation.
- Define CPU and memory requests and limits for all workloads.
- Continuously scan running workloads for configuration drift.