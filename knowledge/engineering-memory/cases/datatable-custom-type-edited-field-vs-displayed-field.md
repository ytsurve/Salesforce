# Inline-edited value stays stale until save when a datatable column edits one field but displays another

## Symptom

In a `lightning-datatable` with custom column types, inline editing "worked" - the draft saved
correctly - but the cell kept showing the OLD value from the moment of editing until a save round
trip completed. Picking a new lookup record, or typing a new date, left the previous text visible
in the cell. Standard Salesforce inline edit shows the new value immediately, highlighted as a
pending change.

Notably, one editable column behaved correctly and the others did not: a plain text column whose
`fieldName` was also the field rendered in view mode previewed fine.

## Evidence pattern

- The columns that failed were the ones where the edited field and the displayed field are
  different: lookup columns edit an Id (`WhatId`/`WhoId`/`OwnerId`) but render a *name*, and the
  date column edited an ISO value but rendered pre-formatted display text. The column that worked
  edited and displayed the same field.
- A first fix attempt added `onchange` handlers to the custom `editTemplate` markup, dispatching
  events up to the parent. This produced **no observable change at all** - not a wrong value, no
  console error, simply no effect - which is consistent with handlers referenced from an
  `editTemplate` not being bound to the class that extends `LightningDatatable`. Edit templates
  are instantiated by the datatable's own internal edit panel, not by the extending component, so
  that is not a usable hook point. (Handlers in the *view* template of a custom type do work.)

## Root cause

`lightning-datatable` can only refresh a cell's visible text by itself when the field being edited
is the field being rendered. When a custom type edits field A and displays field B, nothing in the
platform knows how to derive the new B from the new A - so the cell legitimately keeps rendering
the stale B until the row is reloaded from the server.

## Safe fix pattern

Do the derivation in the parent component, driven by the datatable's **public `cellchange` event**
(not by hooks inside the edit template):

- `oncellchange` on the datatable; merge `event.detail.draftValues` into the component's
  `draftValues` so the pending-change highlight and the Save/Cancel bar behave normally.
- For each committed draft, compute the new display value and patch it onto the row data:
  - date/datetime: format client-side (a stand-in until save reloads the server-formatted value).
  - lookup: resolve the new Id's display text server-side. Derive the object type from the Id
    itself (`Id.getSObjectType()`) rather than passing it in - a polymorphic lookup can be
    re-pointed at a different object mid-edit - and derive the display field from the describe's
    own name field (`isNameField()`), not a hardcoded `Name`, since objects such as Case and
    Contract use their number instead.
  - if the record is not readable, leave the existing text rather than blanking the cell; it is
    only a cosmetic preview.
- Keep a pristine copy of the loaded rows and restore it on cancel. The display patches are local
  edits to row data, so without this a cancelled edit leaves the new text visible in a cell whose
  record never changed.

## Test approach

The server-side name resolution is ordinary unit-testable Apex - cover a `Name`-field object, a
number-field object (Case/Contract), and a null Id. The preview behaviour itself is client-side
rendering and needs a real-browser check: edit a lookup, click away, confirm the new label appears
before saving, then cancel and confirm the original label returns.

## Prevention

When adding an editable column to a custom-type datatable, check up front whether `fieldName` (the
edited field) is the same as the field rendered in view mode. If it is not, the display repaint is
part of the work, not an afterthought - budget for the `cellchange` handler and, for lookups, the
server call that resolves the label.
