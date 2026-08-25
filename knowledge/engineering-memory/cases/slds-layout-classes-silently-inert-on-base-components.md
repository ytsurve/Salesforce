# SLDS layout classes silently do nothing when applied around base components

## Symptom

A component toolbar (search input + button, with a two-button view toggle beneath it) rendered
wrong in three ways at once, across several attempts to fix it:

- The two toggle buttons rendered with a visible gap between them instead of as one joined group.
- The search input never widened, staying at its intrinsic width despite being given a
  grow/percentage-width column.
- The toggle row sat a few pixels to the LEFT of the search row above it, so the toolbar looked
  misaligned against the rest of the card.

No errors, no console warnings - the markup simply had no effect.

## Evidence pattern

Each symptom traced to a different way SLDS's own CSS could not reach what it needed to:

- `slds-button-group` joins its children with rules targeting sibling `.slds-button` elements.
  With `lightning-button` children, each `<button class="slds-button">` lives inside that
  component's own shadow root, so it is never a sibling of another `.slds-button` in the same tree
  and the joining rules never match. The children fall back to default inline spacing - the gap.
- `slds-page-header__row` / `slds-page-header__col-controls` are flex containers that size to their
  content. A child given `flex: 1 1 auto` or a `slds-size_*` percentage inside them has no
  established width to grow into, so the input stayed at its natural size.
- `slds-gutters_*` applies a negative horizontal margin to the row and compensating padding to
  columns. On a wrapped line this pulled the first column out past the intended left edge, which is
  what shifted the toggle row leftwards.
- One attempt relied on a `slds-grow` utility class that had no effect at all in this context,
  which is easy to miss because an inert class looks identical to a correct one in the markup.

## Root cause

SLDS utility and layout classes assume they are styling plain elements in one DOM tree. Base
components put their real markup behind a shadow boundary, and SLDS grid/gutter helpers make
assumptions about the sizing context of their container. Neither fails loudly.

## Safe fix pattern

- For layout inside a component, prefer **explicit flex CSS in the component's own stylesheet** to
  a stack of SLDS grid/gutter classes: put the rows in one flex column container so they share a
  single left edge by construction, and give sized children an explicit width rather than relying
  on flex-grow reaching through ancestors whose sizing is not under your control.
- Where SLDS's own CSS must match sibling elements to work - a joined button group being the clear
  case - use native SLDS markup (`<button type="button" class="slds-button slds-button_neutral">`)
  instead of the base component, and drive active state by swapping the class. Add `aria-pressed`
  for the toggle semantics the base component would have provided.
- If a block element must span the container's width, make it a plain block child of a block
  ancestor rather than a flex item of a shrink-to-fit flex container.

## Test approach

Purely visual; no unit test will catch any of it. These need a screenshot or a look at the rendered
page. Worth checking at more than one viewport width, since the wrapped-line behaviour of gutters
only shows up once a row wraps.

## Prevention

Treat "the class is in the markup" as no evidence that it applied. When a layout does not look
right, check first whether the styling depends on crossing a shadow boundary or on an ancestor's
sizing context - and if so, reach for explicit CSS in the component instead of another SLDS class.
