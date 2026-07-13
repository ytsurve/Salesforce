---
name: apex
description: Salesforce Apex implementation guidance. Use when creating, editing, reviewing, debugging, or testing Apex classes, triggers, Queueables, Batches, Schedulables, selectors, services, domains, test classes, or SOQL/DML-heavy logic.
---

# Apex

For an incident, use `skills/salesforce-debugging/SKILL.md` before proposing code changes. For any release, use `skills/salesforce-release-management/SKILL.md`.

Search existing Apex before writing code. Reuse the repository's trigger, service, selector, domain, and utility patterns.

Prefer configuration or Flow before Apex unless Apex is needed for scale, reuse, complex logic, transaction control, or integration.

Rules:

- Never put business logic directly in triggers.
- Bulkify all logic.
- Never place SOQL or DML inside loops.
- Query only needed fields.
- Enforce sharing, CRUD, FLS, and injection safety.
- Use Custom Metadata or Labels for configurable values.
- Handle partial success where appropriate.
- Avoid `Test.isRunningTest()` unless there is no safer design.

Testing must cover positive, negative, bulk, null, permission, sharing, exception, and edge scenarios where relevant.
