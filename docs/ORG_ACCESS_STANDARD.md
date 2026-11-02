# Org Access Standard

## Before Any Org Operation

Confirm the target alias or username, org type, instance, purpose, and requested scope. Treat an ambiguous default org as unsafe. State the intended target in the plan and again before a production operation.

## Read-Only Work

Scoped describe calls, read-only SOQL, metadata retrieval to `org-snapshots/`, deployment reports, and local diffing are permitted after confirming target and scope. Retrieve the smallest component set that answers the question. In production, even read-only work runs only when the user's current request explicitly asks to look in production.

## State-Changing Work

Creating debug-log trace flags, changing data, metadata, permissions, org configuration, deployments, cancellations, or authentication state requires explicit approval. A temporary change is still a change.

Validate-only (check-only) deployments, quick deploys, and Apex test runs also count as org operations that need explicit approval. They leave a permanent Deployment Status or test-history entry under the authenticated user's name, even when nothing is saved. Ask before each one, naming the command and target org. A yes covers only that operation. Choosing a method ("apply via CLI") is not approval to run it.

## Data Handling

Query only fields needed for the investigation. Do not output or store credentials, access tokens, customer data, passwords, or unredacted logs. Use record IDs only when essential; redact values in saved artifacts.
