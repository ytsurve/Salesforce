# Salesforce AI Engineering Standard

This repository is a production-safe operating brain for Salesforce architecture, administration, development, debugging, releases, and communication.

## Start Here

1. `AGENTS.md` is the short, always-loaded contract.
2. `CODEX.md` routes a task to the right standard and skill.
3. `docs/` contains detailed, task-specific standards.
4. `skills/` contains reusable workflows.
5. `templates/` and `checklists/` turn standards into repeatable work.

## Operating Model

Every task is evidence first, plan first, approval gated, minimally changed, verified, rollback ready, and explained in plain language. A production deployment is not ready without a pre-change baseline and a tested rollback approach.

## Metadata Model

Keep approved source in the actual Salesforce project repository. Retrieve affected production metadata into ignored `org-snapshots/` folders for comparison; do not treat a full production dump as permanent truth. See `docs/METADATA_SNAPSHOT_STANDARD.md`.

## Structure

- `docs/`: detailed rules and operating standards
- `skills/`: focused reusable Salesforce workflows
- `checklists/`: pre-change, testing, production, and release gates
- `templates/`: approval, incident, manager, rollback, and RCA formats
- `knowledge/engineering-memory/`: sanitized lessons and skill-improvement candidates
- `org-snapshots/`: local, ignored, case-specific metadata snapshots

Do not store secrets, access tokens, customer data, or unredacted production logs in this repository.
