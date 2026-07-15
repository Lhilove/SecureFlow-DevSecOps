# Threat Model — PostgreSQL Database

## System Overview

The PostgreSQL database serves as the primary persistent storage for the SecureFlow platform. It stores authentication data, user profiles, account balances, transaction history, virtual card information, and other application data.

The database is only accessible by internal services running within the Kubernetes cluster. Direct access from the public internet is prohibited. Authentication and Transaction Services communicate with PostgreSQL using dedicated service accounts, while database credentials are securely managed through HashiCorp Vault.

Because the database contains highly sensitive financial and personal information, it represents one of the highest-value assets in the SecureFlow architecture.

---

## Assets

- User Accounts
- Password Hashes
- Account Balances
- Transaction History
- Virtual Card Records
- JWT Blacklist / Session Data
- Database Credentials
- Database Backups
- Database Logs
- Encryption Keys
- Database Schemas
- Stored Procedures

---

## Trust Boundaries

- Authentication Service → PostgreSQL
- Transaction Service → PostgreSQL
- PostgreSQL → Backup Storage
- Database Administrators → PostgreSQL
- PostgreSQL → Monitoring and Logging Systems

---

## STRIDE Analysis

### Spoofing

- Attacker steals database credentials from a compromised application.
- Unauthorized application impersonates a trusted service account.
- Database administrator credentials are compromised.

### Tampering

- SQL Injection modifies account balances.
- Unauthorized modification of transaction records.
- Database backups altered before restoration.
- Stored procedures modified to execute malicious logic.

### Repudiation

- Database changes occur without audit logging.
- Administrators modify records without accountability.
- Missing transaction logs prevent forensic investigations.

### Information Disclosure

- SQL Injection exposes sensitive customer data.
- Database backups are stored without encryption.
- Sensitive information exposed through verbose database errors.
- Weak database permissions allow unauthorized data access.
- Personally Identifiable Information (PII) leaked through logs.

### Denial of Service

- Long-running queries exhaust database resources.
- Connection pool exhaustion prevents legitimate access.
- Storage exhaustion due to uncontrolled database growth.
- Lock contention delays financial transactions.
- Database crashes caused by malicious query execution.

### Elevation of Privilege

- Application service account has excessive database privileges.
- SQL Injection escalates privileges through administrative functions.
- Weak database role separation allows unauthorized schema changes.
- Misconfigured permissions allow users to execute privileged operations.

---

## Attack Scenarios

### Scenario 1: SQL Injection in Transaction Service (Critical)

An attacker exploits a SQL Injection vulnerability in the Transaction Service. Arbitrary SQL commands are executed against PostgreSQL, allowing extraction of customer records, modification of account balances, and deletion of financial data.

Impact: Critical; complete compromise of financial records, customer data exposure, and regulatory violations.

---

### Scenario 2: Stolen Database Credentials (High)

An attacker compromises an application pod and retrieves database credentials from environment variables or improperly secured configuration files. Using these credentials, the attacker directly accesses PostgreSQL and extracts sensitive financial information.

Impact: High; unauthorized database access, financial fraud, and customer data breach.

---

### Scenario 3: Backup Theft (High)

Database backups stored in cloud object storage are not encrypted or are accessible through overly permissive IAM policies. An attacker downloads historical backups containing customer financial data.

Impact: High; large-scale disclosure of sensitive customer information and long-term exposure of historical records.

---

## Mitigations

### Existing Controls

- PostgreSQL is only accessible from internal services.
- Database credentials are managed through HashiCorp Vault.
- Kubernetes Network Policies restrict database access.
- Runtime monitoring provided by Falco.
- CI/CD pipeline scans application code for SQL Injection risks.

### Gaps and Recommendations

- Enforce least-privilege database roles.
- Enable TLS for all database connections.
- Encrypt data at rest.
- Encrypt database backups.
- Enable PostgreSQL audit logging.
- Rotate database credentials regularly.
- Implement Row-Level Security (RLS) where appropriate.
- Use parameterized queries and prepared statements.
- Monitor unusual query patterns.
- Regularly test backup restoration procedures.