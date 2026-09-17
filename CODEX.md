# CODEX.md

`AGENTS.md` is the always-loaded operating contract for this repository.

Start each task with a plan and evidence. Do not edit or operate on a Salesforce org until the plan receives explicit approval.

Load only the relevant material:

- Debugging: `.claude/skills/salesforce-debugging/SKILL.md`
- Org inspection or metadata retrieval: `.claude/skills/salesforce-cli/SKILL.md`
- Deployment or rollback: `.claude/skills/salesforce-release-management/SKILL.md`
- Apex, Flow, LWC, or security work: matching `.claude/skills/*/SKILL.md`

Those files are canonical despite the `.claude/` prefix; no second copy exists. OpenAI-side skill
adapters live in `integrations/openai/`.

Use `templates/` for approval plans, incident summaries, release records, and root-cause analyses. Record reusable, sanitized lessons in `knowledge/engineering-memory/`.
