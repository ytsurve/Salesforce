# Production Safety Standard

## Non-Negotiable Gates

No production change without: confirmed target org, explicit approval, scoped plan, evidence, pre-change baseline, test plan, rollback path, and named monitoring check.

## Protect the Org

- Do not run destructive metadata, data, permission, or deployment operations speculatively.
- Avoid direct production edits when a validated release artifact is available.
- Do not mix unrelated changes in one release.
- Do not include destructive changes, field type conversions, deletion, automation activation, or permission expansion without an explicit impact review.
- Treat email, integrations, scheduled jobs, and asynchronous automation as side effects requiring separate verification and compensation planning.

## Stop Conditions

Pause and escalate when target identity is unclear, evidence conflicts, business impact is wider than planned, a rollback artifact is missing, tests fail, or new side effects appear. Do not proceed merely because a change seems small.
