# Deployment Standard

## Release Preparation

Use `skills/salesforce-release-management/SKILL.md`, `checklists/deployment.md`, and `templates/production-change-log.md`.

Prepare one scoped release artifact from a known Git commit. Confirm dependencies, API version, target org, test level, deployment window, approver, monitoring owner, and rollback artifact. Validate before production; record the validation job/report and result.

## Go/No-Go

Deploy only after validation succeeds, the target is reconfirmed, the component list matches approval, and the rollback plan can be executed. A quick deployment is a release acceleration technique, not a substitute for approval or rollback preparation.

## After Deployment

Record deployment ID, time, result, components, tests, and immediate verification. Monitor the agreed business path, automation errors, integration behavior, and affected-user access. If success criteria fail, invoke the rollback decision process immediately.
