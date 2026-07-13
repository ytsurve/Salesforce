# Planning Standard

## Required Plan

Create a concise plan before every implementation, configuration, deployment, or org-changing action. Use `templates/approval-plan.md`.

Include:

- Requested outcome and affected users
- Verified evidence and explicit unknowns
- Affected metadata, records, automation, integrations, and permissions
- Recommended option and meaningful alternatives
- Scope, dependencies, and risks
- Test scenarios and success criteria
- Rollback method, owner, and decision trigger
- Exact approval requested

## Approval Gate

Wait for explicit approval after presenting the plan. Approval to investigate does not approve a fix, deployment, data change, permission change, or rollback.

## Emergency Work

For a live incident, prepare a short emergency plan: impact, containment, evidence, minimal action, rollback, and approver. Urgency never removes the need to identify the target org and preserve a pre-change baseline.
