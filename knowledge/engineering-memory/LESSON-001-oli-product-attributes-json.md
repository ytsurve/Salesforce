# LESSON-001 — Opportunity Product attribute fields are driven by a JSON field, not the fields themselves

Sanitized. Case detail (org, record Ids, account names, baseline extracts, change log) is held
locally under `org-snapshots/` and is not reproduced here.

## Context

A bulk request asked for a set of attribute fields to be populated on a batch of Opportunity
Products. The fields were loaded successfully by CSV. Reports and the Opportunity Product record
page showed the correct values. The requesters still reported that "the fields are blank" on the
custom **Add/edit Products** product-selector page, and asked for the attribute configuration to be
set up — which turned out to already exist.

The org uses a custom (non-namespaced, vendor-authored) product selector on Opportunity: a
Visualforce page reached from an Opportunity custom button, with a supporting Apex controller and
handler class, an attribute-definition custom object per product, and a hierarchy custom setting
mapping each attribute type to an Opportunity Product field.

## Root cause

The selector reads and writes **only** a long-text JSON field on the Opportunity Product. It ignores
the individual attribute fields when rendering.

The handler method that produces the line item for both render and save does this, in order:

1. Iterates the attribute-to-field mapping setting and **sets every mapped field to null**.
2. Returns early if the JSON field is null.
3. Otherwise deserializes the JSON and repopulates each mapped field from the selected labels.

So a load that writes the individual fields but leaves the JSON empty produces exactly the reported
symptom: data correct everywhere except the selector, which has nothing to render.

## Latent hazard — the more important half

Because step 1 runs **before** the early return in step 2, opening the selector on a line item whose
JSON is blank and clicking Save **nulls every mapped attribute field**, with nothing to restore them
from. A UI visit that looks read-only is destructive.

This inverts the usual triage instinct. The "harmless" advice — "just open the page and look" — is
the thing that causes data loss. Warn the business before asking them to reproduce.

## Evidence pattern

Confirm in this order. Four cheap eliminations come before the one that matters:

1. Are the individual fields actually populated? SOQL, grouped, with a null count per field.
2. Are those fields on the Opportunity Product layout, and does the Lightning record page render
   that layout (a `force:detailPanel` region means it does)?
3. Do the reporting users have Read field-level security on them?
4. Do the attribute-definition records exist for that product, active and flagged visible, and does
   the attribute-to-field mapping setting cover each type?
5. **Is the JSON field populated?** Note it is a long text area, so it cannot be filtered in SOQL —
   select it and count blanks client-side.

In this case 1–4 were all correct and only 5 was empty. Recording the order is the reusable part.

Also worth checking early: whether the reported screen is the record detail page, the related list
on the parent, or the selector. They fail for different reasons and the fix differs. A screenshot
settles it faster than any query.

## Safe fix pattern

Backfill the JSON field; do not re-load the individual fields.

Shape, derived from a line item that the selector itself had authored — copy a real one rather than
inventing it:

- A wrapper object holding a list of attribute types.
- Each type carries its type name and a list of selected entries.
- Each selected entry carries the **attribute definition record Id** as its value, the
  human-readable option as its label, plus the active / default / visible / package-use flags
  mirrored from the definition record.
- The per-type `field` key appears as the literal string `"undefined"` in selector-authored
  records. Reproduce it; do not "correct" it.

Where every record in the batch shares the same selections, one identical JSON string serves the
whole load.

## Trade-offs

Writing the JSON directly bypasses the UI that normally maintains it, so the JSON and the individual
fields can drift if only one is written. Accepted here because the alternative — having users
re-pick every dropdown on each record by hand — is slower and itself risks the save-wipe above. The
mitigation is to always write both representations in the same pass.

## Test approach

- Dry run in a full-copy sandbox first, and **verify the attribute definition Ids match** between
  the sandbox and production rather than assuming a refresh preserved them. Matching Ids are what
  make a single payload portable; differing Ids mean the payload must be rebuilt per org.
- Single-record pilot before the batch, verified, then the remainder.
- Assert the stored JSON is **byte-identical** to the intended string, not merely non-empty.
- Assert the individual attribute fields, quantity and pricing are unchanged.
- Assert child schedule row counts are unchanged — the object carries several active
  record-triggered flows and an all-context Apex trigger that cascade into child schedule records.
- Confirm in the **UI** that the dropdowns render pre-selected. The data assertions do not prove
  this; only opening the page does.

## Impact and rollback

- Impact: one field written per record. No metadata, permission or configuration change.
- Rollback artifact: a pre-change extract of the affected records, captured before the first write.
- Reverse action: re-load the extract, blanking the JSON field.
- No further compensation needed when nothing but that field was written and child record counts
  are unchanged. Confirm both before declaring the rollback sufficient.

## Future prevention

- Any bulk load touching attribute-mapped Opportunity Product fields **must write the JSON field in
  the same pass**. Treat the individual fields alone as an incomplete load.
- Before reporting a selector-backed field as "populated", open the selector. A report column is not
  evidence about that page.
- When a user says a field is blank but SOQL says otherwise, suspect a second surface with its own
  source of truth before suspecting the data.

## Known open risk

Only the records in this request were remediated. **Any other Opportunity Product with a blank JSON
field remains exposed to the save-wipe described above.** No org-wide scan has been run. This is
open, not closed.

## Operational gotchas

Both cost real time in this case:

- Windows PowerShell `-Encoding utf8` writes a UTF-8 BOM. The Bulk API rejects it as
  `InvalidBatch : Failed to parse CSV. Found unescaped quote` with 0 records processed. Write CSVs
  with `System.Text.UTF8Encoding($false)`, and do not round-trip a JSON-bearing CSV through Excel —
  it re-quotes the payload.
- `sf api request rest --method PATCH` against `/composite/sobjects` hung indefinitely with no
  request reaching the org. Use the Bulk API path for data loads.
