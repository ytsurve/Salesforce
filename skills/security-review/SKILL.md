---
name: security-review
description: Salesforce security review guidance. Use when reviewing CRUD, FLS, sharing, user mode, stripInaccessible, SOQL injection, XSS, secrets, Named Credentials, permissions, Experience Cloud exposure, or sensitive data handling.
---

# Security Review

For an access or data-exposure incident, use `skills/salesforce-debugging/SKILL.md` to establish the affected user context and evidence before changing permissions or code. For any release, use `skills/salesforce-release-management/SKILL.md`.

Treat security as a release gate.

Check:

- Sharing model and class sharing keywords
- CRUD and FLS enforcement
- User mode database operations where appropriate
- `Security.stripInaccessible()`
- SOQL injection
- XSS and unsafe rendering
- Named Credentials and secret handling
- Permission Sets and Permission Set Groups
- Guest user and Experience Cloud exposure
- Sensitive fields and logging

Do not approve a change that relies on hidden permissions, hardcoded secrets, broad object access, or unverified assumptions about user visibility.
