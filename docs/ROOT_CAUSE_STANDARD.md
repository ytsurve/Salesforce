# Root Cause Standard

Use a root-cause analysis when an incident affects production users, recurs, causes incorrect data, exposes a material control gap, or needs a manager explanation.

Separate:

- **Symptom:** what users observed
- **Root cause:** the condition that directly produced it
- **Contributing factors:** conditions that allowed or amplified it
- **Fix:** the specific change that removes or controls the cause
- **Prevention:** monitoring, tests, guardrails, documentation, or process improvements

Every root-cause claim must cite evidence. Do not use vague conclusions such as `configuration issue` or `user error` without naming the exact configuration, condition, and proof. Use `templates/root-cause-analysis.md`.
