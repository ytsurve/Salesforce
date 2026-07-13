---
name: lwc
description: Lightning Web Component guidance. Use when creating, editing, reviewing, debugging, or testing Salesforce LWC UI, Apex-backed components, wire adapters, LDS, accessibility, performance, or client-side state.
---

# LWC

Reuse existing component patterns, styling conventions, Apex services, and data access choices.

Prefer Lightning Data Service and wire adapters before imperative Apex when they fit.

Rules:

- Keep components focused.
- Separate UI state, data loading, and business rules.
- Minimize server round trips.
- Handle loading, empty, error, and permission states.
- Do not expose sensitive data.
- Escape and validate user-controlled values.
- Follow accessibility basics for labels, keyboard use, and semantic markup.
- Add Jest tests when behavior is meaningful or risky.

When Apex is needed, verify CRUD/FLS/sharing enforcement on the server side.
