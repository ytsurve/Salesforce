---
name: salesforce-debugging
description: Diagnose Salesforce incidents and unexpected behavior using evidence, safe reproduction, execution tracing, root-cause analysis, approval-gated fixes, and plain-language incident reports. Use for Flow, formula, validation rule, Apex, permission, sharing, integration, email, scheduled-job, deployment, or automation troubleshooting.
---

# Salesforce Debugging

Read `docs/DEBUGGING_STANDARD.md`, `docs/EVIDENCE_STANDARD.md`, `docs/ROOT_CAUSE_STANDARD.md`, and `docs/OUTPUT_STANDARD.md` before acting. Read production and org-access standards when an org is involved.

## Workflow

1. Capture symptom, user, record/action, time, expected result, actual result, scope, and impact.
2. Preserve evidence and reproduce safely; do not alter production state to create evidence without approval.
3. Classify the path: formula/validation, Flow, Apex, access, integration, email, scheduled work, or deployment.
4. Trace actual execution and retrieve only involved metadata into a local snapshot.
5. Test hypotheses against evidence. Separate facts, inference, and unknowns.
6. State root cause and contributing factors only when evidence supports them.
7. Create `templates/approval-plan.md`; do not fix until explicitly approved.
8. After approval, make the smallest change, run the defined checks, and complete `templates/incident-summary.md`.

## Diagnostic Prompts

- Formula or validation: capture formula text, evaluated inputs, error, and user context.
- Flow: identify active version, entry criteria, element, inputs, fault path, order-of-execution dependencies, and permissions.
- Apex: capture stack trace/test, inputs, limits, sharing/CRUD/FLS, async boundary, and integration response.
- Access: prove the affected user, object/field/action, permission assignments, record ownership, sharing, and expected policy.

Never apply random configuration changes, disable controls, or call a probable cause a confirmed root cause.
