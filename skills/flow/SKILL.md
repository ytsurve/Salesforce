---
name: flow
description: Salesforce Flow guidance. Use when creating, reviewing, debugging, or choosing Record-Triggered Flows, Screen Flows, Scheduled Flows, automation design, validation alternatives, approval routing, or Flow-vs-Apex decisions.
---

# Flow

For a failing or unexpected Flow, use `skills/salesforce-debugging/SKILL.md` before changing metadata. For any release, use `skills/salesforce-release-management/SKILL.md`.

Use Flow for straightforward automation, guided UI, approvals, routing, and simple data updates.

Avoid Flow when logic needs complex transactions, heavy looping, advanced error handling, reusable algorithms, large data volume behavior, or integration orchestration that is safer in Apex.

Rules:

- Check existing Flows before creating new automation.
- Avoid duplicated logic across Flow and Apex.
- Keep entry criteria selective.
- Handle fault paths.
- Avoid unnecessary updates that retrigger automation.
- Use clear names and descriptions.
- Consider order of execution and recursion risk.

Review related validation rules, triggers, approval processes, assignment rules, duplicate rules, and permission behavior before finalizing a Flow solution.
