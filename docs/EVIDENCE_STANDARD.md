# Evidence Standard

## Evidence Hierarchy

Use the strongest available source:

1. Reproduction, deployment result, test result, debug log, or direct org inspection
2. Version-controlled metadata and repository history
3. Salesforce documentation and vendor integration documentation
4. User description or remembered behavior
5. Hypothesis

State the source beside important claims. A helpful format is `Evidence: <source>; conclusion: <fact>`. Preserve a link, file path, component API name, command result summary, or log timestamp without exposing sensitive values.

## Minimum Evidence By Task

- Formula or validation rule: current formula, field values, error text, and user context.
- Flow or automation: version/status, entry conditions, failing element, prior automation, and fault/error details.
- Apex: stack trace or failing test, call path, input data shape, and relevant code.
- Access issue: affected user, object/field/action, permission assignment, sharing context, and expected access.
- Deployment: source commit, target org identity, validation report, component list, and test result.

## Prohibited Shortcuts

Do not use screenshots alone as proof when metadata or logs can be inspected. Do not infer permissions from a profile name. Do not infer production state from local source. Redact sensitive data before storing evidence.
