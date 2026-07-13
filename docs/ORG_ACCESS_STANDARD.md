# Org Access Standard

## Before Any Org Operation

Confirm the target alias or username, org type, instance, purpose, and requested scope. Treat an ambiguous default org as unsafe. State the intended target in the plan and again before a production operation.

## Read-Only Work

Scoped describe calls, read-only SOQL, metadata retrieval to `org-snapshots/`, deployment reports, and local diffing are permitted after confirming target and scope. Retrieve the smallest component set that answers the question.

## State-Changing Work

Creating debug-log trace flags, changing data, metadata, permissions, org configuration, deployments, cancellations, or authentication state requires explicit approval. A temporary change is still a change.

## Data Handling

Query only fields needed for the investigation. Do not output or store credentials, access tokens, customer data, passwords, or unredacted logs. Use record IDs only when essential; redact values in saved artifacts.
