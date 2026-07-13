# Rule Hierarchy

## Priority

1. User instruction and applicable safety requirements
2. Data protection and production safety
3. `AGENTS.md`
4. This hierarchy
5. Relevant standards in `docs/`
6. Relevant skills in `skills/`
7. Repository evidence and established patterns
8. General best practices

## Conflict Handling

Follow the higher rule. If a request conflicts with production safety, evidence requirements, or stated business intent, stop and explain the conflict before any change.

## Rule Levels

- Critical: never bypass without explicit user direction and a documented risk decision.
- Strong: follow by default; record a reason to override.
- Guidance: apply when it improves safety, clarity, or maintainability.

No skill, template, or checklist can authorize a production change, replace evidence, or override an approval gate.
