# CODEX.md

Use `AGENTS.md` as the source of truth for Codex behavior in this repository.

Keep this file intentionally short so it loads quickly and does not duplicate rules.

Required behavior:

- Read `AGENTS.md` first.
- Load only the relevant docs, standards, skills, templates, and knowledge files for the current task.
- Prefer evidence from the repository over assumptions.
- Ask when Salesforce metadata or business intent cannot be verified.
- Keep changes focused and reversible.

For Salesforce implementation work, use the matching skill:

- Apex: `skills/apex/SKILL.md`
- Flow: `skills/flow/SKILL.md`
- LWC: `skills/lwc/SKILL.md`
- Security review: `skills/security-review/SKILL.md`

For planning and completion formats, use:

- `templates/plan.md`
- `templates/change-log.md`
