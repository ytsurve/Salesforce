---
name: salesforce-cli
description: Safely inspect Salesforce orgs, metadata, deployments, and read-only data with Salesforce CLI. Use when confirming an org target, describing objects, running scoped read-only SOQL, retrieving metadata, comparing local source, or reporting deployment status.
---

# Salesforce CLI Safety

Read `docs/ORG_ACCESS_STANDARD.md` and `docs/METADATA_SNAPSHOT_STANDARD.md`. Also read `docs/PRODUCTION_SAFETY_STANDARD.md` for production targets.

## Target Discipline

Before a command, state the intended alias or username, environment type, and scope. Never rely on an ambiguous default org. Do not print access tokens, auth URLs, passwords, customer data, or raw secrets.

## Read-Only Workflow

1. Confirm target identity and user request.
2. Use scoped describe, SOQL, deployment report, or retrieval commands only.
3. Query only needed fields and retrieve only affected metadata.
4. Save retrievals under `org-snapshots/<case-or-date>/`, never over approved source.
5. Diff snapshot against the repository baseline and summarize evidence.

## Approval Boundary

Treat deployments, cancellation, data mutation, permission changes, trace flags/debug logging, auth changes, and any org configuration operation as state-changing. Stop for explicit approval before those actions.

## Reporting

Record target org, scope, command intent, timestamp, and summarized result. Keep personal data and secrets out of saved reports.
