# Threat Model — Transaction Service

## System Overview

The Transaction Service manages all financial operations within the SecureFlow platform. It provides APIs for transferring funds, checking account balances, managing virtual cards, and retrieving transaction history.

The service receives authenticated requests from the Frontend/BFF after users are validated by the Authentication Service. It stores transaction data in PostgreSQL and relies on JWT claims to authorize financial operations.

Because this service directly handles financial assets, it is considered one of the highest-value targets in the platform.

---

## Assets

- Account Balances
- Transaction Records
- Virtual Cards
- User Account IDs
- Beneficiary Information
- JWT Claims
- Transaction Database
- Transaction Logs
- API Endpoints
- Business Logic

---

## Trust Boundaries

- Frontend/BFF → Transaction Service
- Authentication Service → Transaction Service
- Transaction Service → PostgreSQL
- Transaction Service → HashiCorp Vault
- Transaction Service → Internal APIs (Future Integrations)

---

## STRIDE Analysis

### Spoofing

- Attacker forges or steals JWT tokens to impersonate legitimate users.
- Compromised service impersonates another internal service.
- API requests replayed using stolen access tokens.

### Tampering

- Transaction amount modified before processing.
- Destination account manipulated during fund transfer.
- API parameters altered to bypass validation.
- Transaction records modified in the database.
- Business logic manipulated to bypass transfer limits.

### Repudiation

- User performs unauthorized transfers and denies initiating them.
- Administrative transaction changes are not logged.
- Missing audit trails prevent forensic investigations.
- Transaction approvals cannot be linked to individual users.

### Information Disclosure

- Users access other customers' transaction histories (IDOR/BOLA).
- Account balances exposed through broken authorization.
- Transaction logs leak personally identifiable information (PII).
- Verbose API errors reveal database structure.
- Sensitive financial data exposed through insecure logging.

### Denial of Service

- Flooding transfer endpoints with automated requests.
- Expensive balance queries exhaust database resources.
- Transaction queue saturation delays legitimate payments.
- Database locking caused by concurrent requests.
- Large payloads consume application resources.

### Elevation of Privilege

- Broken authorization allows regular users to access administrative endpoints.
- Missing ownership checks allow users to modify another customer's transactions.
- Mass Assignment permits modification of protected fields.
- JWT role claims manipulated to obtain elevated privileges.

---

## Attack Scenarios

### Scenario 1: Broken Object Level Authorization (Critical)

An attacker authenticates as a normal user and modifies the transaction ID within the API request. The application fails to verify ownership of the requested transaction and returns another customer's financial records.

Impact: Critical; unauthorized disclosure of sensitive financial data, regulatory violations, and customer privacy breaches.

---

### Scenario 2: Race Condition in Fund Transfers (Critical)

An attacker submits multiple transfer requests simultaneously before the account balance is updated. Due to insufficient concurrency controls, multiple transfers are processed using the same available balance.

Impact: Critical; unauthorized overdrafts, financial losses, and inconsistent account balances.

---

### Scenario 3: Mass Assignment Vulnerability (High)

The transfer endpoint accepts additional parameters supplied by the client. An attacker includes protected fields such as `account_role`, `is_verified`, or `transfer_limit`, allowing unauthorized modification of sensitive attributes.

Impact: High; privilege escalation, bypass of business rules, and unauthorized financial operations.

---

## Mitigations

### Existing Controls

- Authentication performed through JWT.
- Sensitive secrets managed by HashiCorp Vault.
- Communication occurs within the Kubernetes cluster.
- Runtime monitoring provided by Falco.
- Network segmentation enforced through Kubernetes Network Policies.

### Gaps and Recommendations

- Implement object-level authorization checks on every resource.
- Enforce least privilege using Role-Based Access Control.
- Validate ownership of accounts before processing requests.
- Implement optimistic or pessimistic locking for financial transactions.
- Prevent Mass Assignment using explicit allowlists.
- Apply rate limiting to transaction endpoints.
- Use idempotency keys for payment requests.
- Log all financial operations in immutable audit logs.
- Encrypt sensitive financial data both in transit and at rest.
- Perform comprehensive input validation on all API parameters.