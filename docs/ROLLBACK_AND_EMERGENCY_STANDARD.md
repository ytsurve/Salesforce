# Rollback And Emergency Standard

## Principle

Prepare recovery before a production change. A successful metadata deployment is committed; recovery usually means deploying the known-good prior metadata as a new release. Do not promise automatic rollback for data, emails, integrations, or asynchronous work.

## Required Rollback Artifact

Before approval, record:

- Pre-change Git commit and exact component list
- Verified pre-change metadata snapshot or release artifact
- Reverse deployment package and dependencies
- Validation/test approach for the reverse deployment
- Data backup or compensation procedure where records may change
- Integration, email, scheduled-job, and automation side-effect plan
- Trigger to rollback, decision owner, executor, and communication owner

## Emergency Modes

1. **Contain:** deactivate only an approved, reversible feature or stop a release in progress when safe.
2. **Rollback metadata:** deploy the verified pre-change artifact, then run focused verification.
3. **Compensate data:** use an approved, auditable restore or correction procedure. Never mass-edit production data without a separate plan and approval.
4. **Recover side effects:** pause or compensate integrations, notifications, and jobs with the responsible owners.

## Incident Communication

State impact, containment status, root cause confidence, action taken, recovery status, remaining risk, and next update time. Use `templates/incident-summary.md`.
