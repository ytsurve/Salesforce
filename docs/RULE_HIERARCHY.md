# Rule Hierarchy

## Priority

1. User instruction
2. Safety and data protection
3. `AGENTS.md`
4. This rule hierarchy
5. Relevant standards in `docs/`
6. Relevant skills in `skills/`
7. Existing repository patterns
8. General best practices

## Conflict Handling

When two rules conflict, follow the higher-priority rule. If conflict remains, stop and explain the issue before making changes.

## Rule Levels

- Critical: must follow unless the user explicitly overrides and risk is acceptable.
- Strong: follow by default; override only with written justification.
- Guidance: apply when useful and consistent with local patterns.

## Resolution Rule

Do not use a lower-level skill or checklist to justify violating user instructions, security requirements, or repository architecture.
