# Security Policy

## Supported Branches

Security fixes are developed on `dev`, validated on `staging`, and promoted to `production`.

## Reporting a Vulnerability

Do not open a public issue for suspected secrets, authentication bypasses, data exposure, payment issues, or smart-contract vulnerabilities.

Report security issues privately to the repository owner, `@peterkilaba-developer`, through GitHub or the currently approved project contact channel. Include:

- affected platform or service
- impact and reproduction steps
- relevant logs, transaction hashes, or screenshots
- whether any user data, keys, funds, or credentials may be exposed

## Secret Handling

Never commit:

- Firebase service-account keys
- `.env` files
- app signing keys or certificates
- deployment signatures or generated outputs
- package caches or `node_modules`

If a secret is committed, rotate or revoke it immediately, remove it from the repository, and purge it from git history before considering the incident closed.
