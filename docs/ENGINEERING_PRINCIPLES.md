# Engineering Principles

## Principles

- Search before building.
- Reuse existing architecture before introducing patterns.
- Prefer readable code over clever code.
- Bulkify Salesforce logic by default.
- Enforce CRUD, FLS, sharing, and injection safety.
- Keep changes focused, reversible, and easy to review.
- Test the behavior, not only the lines.
- Record risks and rollback steps for meaningful changes.

## Decision Order

1. Can standard Salesforce configuration solve it?
2. Can Flow solve it safely and maintainably?
3. Is Apex required for scale, reuse, integration, or complex logic?
4. Does the implementation match the repository's current architecture?
5. Can the change be tested and rolled back?
