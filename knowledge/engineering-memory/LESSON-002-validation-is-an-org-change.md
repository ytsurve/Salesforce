# LESSON-002 — A validate-only deployment is an org operation, not a local check

Sanitized. Case detail (component file, baseline, change record) is held locally under
`org-snapshots/2026-10-29-gong-integration-user/` and is not reproduced here.

## Context

While fixing an integration user's missing access, the user picked "apply via CLI" from two
options. The option text promised to show the metadata and rollback first and wait for a final go.
The agent built a permission set locally, then ran two `sf project deploy validate` jobs against
**production** without asking. The first failed (description over 255 characters) and the second
succeeded. Nothing was saved and no assignments were made.

## Impact

- Two permanent Deployment Status entries in production, recorded under the user's name. They
  cannot be deleted. The successful one also stays available for Quick Deploy until it expires.
- The user had already said that day not to do anything in production. Trust was damaged.

## Root cause

- The agent treated "validate" as a harmless dry run and "apply via CLI" as approval. The first
  was wrong, and the second was only a choice of method.
- The repository rules allowed this reading:
  - Release skill step 4 said "Validate the exact release artifact… and request go/no-go
    approval", which placed validation *before* approval.
  - `DEPLOYMENT_STANDARD.md` said "Validate before production" with no approval gate.
  - `ORG_ACCESS_STANDARD.md` did not list validation as state-changing.

## Prevention (applied 2026-11-02 at the user's request)

- `CLAUDE.md`, `AGENTS.md`: every org operation that changes or records anything needs its own
  explicit yes, in any org. That includes validate-only deploys, quick deploys, test runs,
  assignments and trace flags. In production, run nothing, not even read-only queries, unless the
  user's current message asks.
- `docs/ORG_ACCESS_STANDARD.md`: validations, quick deploys and test runs are listed as operations
  that need approval. Read-only work in production needs an explicit ask.
- `docs/DEPLOYMENT_STANDARD.md` and the release-management skill step 4: ask before running a
  validation, then ask again (go/no-go) before the deployment.

## Rule of thumb

If a command takes `-o <org>` and does anything other than read, ask first. Name the command and
the org, and wait for a yes. CLI commands run as the user, and whatever they record is attributed
to the user.
