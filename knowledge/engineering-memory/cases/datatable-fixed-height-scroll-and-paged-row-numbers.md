# Datatable inline-edit Save/Cancel unreachable, and row numbers restarting on every page

Two independent defects in the same paged `lightning-datatable`, both caused by leaving a datatable
property at its default.

## Symptom

1. Editing a cell anywhere in a 50-row page put the inline-edit Save/Cancel bar below the last row,
   so the user had to scroll past all 50 rows to commit a change made in row 2.
2. Page 2 of the list numbered its rows 1-50 again instead of continuing 51-100, even though the
   page's own range label correctly read "51-100".

## Evidence pattern

- For (1), a first attempt wrapped the datatable in a `div` with `max-height` + `overflow-y: auto`.
  This changed nothing about the symptom: the *wrapper* scrolled while the table inside still laid
  itself out at its full 50-row height, so the bar stayed pinned below the last row. Moving the
  bound height onto the datatable element itself produced the standard behaviour (frozen header,
  body scrolling internally, edit bar docked at the bottom of the visible box).
- For (2), the row-number column appears automatically once any column is editable, and it always
  numbers from 1 for the rows currently in `data` - it has no knowledge of server-side paging.

## Root cause

- `lightning-datatable` only enters its internal-scroll mode when **the datatable element has a
  definite height**. A `max-height` on an ancestor does not trigger it; the table renders at full
  content height and the ancestor scrolls instead. The inline-edit bar is positioned relative to
  the table, so it follows the table's full height.
- Row numbers are per-render, starting at 1. Continuing the sequence across pages requires
  `row-number-offset`.

## Safe fix pattern

- Set a definite height on the datatable element (e.g. a `height` in component CSS applied via a
  class on the element, with a `min-height` floor), not `max-height`, and not on a wrapper.
- Pass `row-number-offset = (pageNumber - 1) * pageSize` alongside `show-row-number-column`.

## Test approach

Both are client-side rendering concerns that unit tests will not catch. Verify in the browser:
edit a cell in the first visible row of a full page and confirm Save/Cancel is reachable without
scrolling; page forward and confirm the first row number continues the sequence.

## Prevention

For any server-paged, inline-editable datatable, treat "definite height on the element" and
`row-number-offset` as part of the initial wiring, in the same way `key-field` and `draft-values`
are. Both defaults are silently wrong for that shape of list: neither produces an error, and the
range label can read correctly while the row numbers disagree with it.
