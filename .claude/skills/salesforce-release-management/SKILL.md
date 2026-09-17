---
name: salesforce-release-management
description: Plan, validate, deploy, monitor, and recover Salesforce releases with explicit approval and rollback readiness. Use for production deployments, validation, quick deployment, release readiness, deployment failures, emergency containment, rollback planning, or post-release verification.
---

# Salesforce Release Safety

Read `docs/DEPLOYMENT_STANDARD.md`, `docs/ROLLBACK_AND_EMERGENCY_STANDARD.md`, and `docs/PRODUCTION_SAFETY_STANDARD.md`. Use `checklists/deployment.md` and `templates/production-change-log.md`.

## Before Approval

1. Confirm target org, release window, approver, component scope, source commit, and dependencies.
2. Prepare a validation plan and capture the pre-change metadata baseline.
3. Prepare the reverse deployment artifact, data compensation approach, side-effect plan, rollback trigger, and named owners.
4. Validate the exact release artifact. Report the result and request go/no-go approval.

## During And After Deployment

Deploy only the approved artifact to the confirmed target. Record the deployment identifier and outcome. Verify the agreed business path, affected user access, automation, integrations, and error signals during the monitoring window.

## If Something Goes Wrong

Contain only through an approved, reversible action. If the rollback trigger is met, deploy the known-good baseline, run focused verification, execute approved data or integration compensation, and communicate status using `templates/incident-summary.md`.

Do not claim that successful metadata deployment can be automatically undone. Treat data, notifications, integrations, and asynchronous work as separate recovery concerns.
