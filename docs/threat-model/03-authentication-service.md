# Threat Model — Authentication Service

## System Overview

The Authentication Service is responsible for user registration, login,
JWT issuance, password reset, refresh token management, and user identity.
It is the primary trust anchor for all authenticated requests made to
the SecureFlow platform.

The service exposes public APIs consumed by the Frontend/BFF and stores
user credentials within the authentication database.

---

## Assets

- User Accounts
- Password Hashes
- JWT Access Tokens
- Refresh Tokens
- JWT Signing Keys
- MFA Secrets (if implemented)
- User Sessions
- Authentication Database
- Password Reset Tokens
- Email Verification Tokens

---

## Trust Boundaries

- Internet → Frontend/BFF
- Frontend/BFF → Authentication Service
- Authentication Service → PostgreSQL
- Authentication Service → Vault
- Authentication Service → JWT Consumers (Transaction Service)

---

## STRIDE Analysis

### Spoofing

- Credential stuffing attacks.
- Password spraying.
- JWT token forgery.
- Session hijacking.
- OAuth account spoofing (future).

### Tampering

- JWT payload modification.
- Password reset token manipulation.
- Account activation token tampering.
- Request parameter manipulation.

### Repudiation

- Login attempts not logged.
- Password reset actions lack audit trails.
- Token revocation events not recorded.

### Information Disclosure

- User enumeration through login responses.
- Password hashes exposed.
- JWT secrets leaked.
- Verbose authentication errors.

### Denial of Service

- Login endpoint brute force.
- Credential stuffing.
- Password reset flooding.
- Registration spam.

### Elevation of Privilege

- Broken Role-Based Access Control.
- JWT algorithm confusion.
- Missing authorization checks.
- Privilege escalation through role manipulation.

---