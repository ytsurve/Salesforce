# Debugging Standard

## Goal

Prove why the observed behavior occurred, then recommend the smallest safe correction. Do not begin by editing the most plausible component.

## Investigation Sequence

1. Capture the symptom: who, what action, record type, time, expected result, actual result, scope, and business impact.
2. Reproduce safely where possible. Preserve the original error, record state, and user context.
3. Classify the path: formula, validation rule, Flow, Apex, permissions/sharing, approval, assignment, duplicate, email, integration, scheduled work, or deployment.
4. Trace the actual execution order and retrieve only involved metadata.
5. Form one or more testable hypotheses. Seek evidence that can disprove each.
6. State the proven root cause, contributing factors, and affected scope.
7. Present an approval plan with a focused fix, tests, rollout, rollback, and monitoring.

## Salesforce-Specific Checks

For a record save, inspect validation rules, record-triggered Flows, Apex, approval/assignment/duplicate rules, workflow/process legacy automation, entitlement logic, managed-package behavior, and field accessibility. For Flow failures, inspect the exact version, failing element, input values, fault path, and user permissions. For Apex, inspect limits, asynchronous boundaries, sharing, CRUD/FLS, bulk behavior, and integration responses.

## Exit Criteria

An issue is not resolved until the fix is verified under the relevant user context and the manager-ready incident summary is complete.
