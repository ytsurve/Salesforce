# Complex object passed to an @AuraEnabled method arrives entirely null on an Aura-hosted LWC page

## Symptom

A Lightning Web Component's imperative Apex calls appeared to silently ignore user input: search
boxes, filter panels, and similar controls had no effect on the results shown, even though the
component's own client-side state was demonstrably correct (confirmed via direct DOM/event
inspection - the right value was in the input, the right value was in the JS event's `detail`).
No error was thrown or surfaced to the user; the call just returned as if the extra parameters
had never been provided.

The failure did not reproduce when the same Apex method was called directly (e.g. via anonymous
Apex with an equivalent, hand-constructed parameter object) - only through the real browser page.

## Evidence pattern

- Instrumented the page's `XMLHttpRequest.prototype.send`/`open` to capture the raw outgoing
  `/aura` POST body and the matching response by action id. The decoded request body showed the
  correct JSON, e.g. `"params":{"request":{"searchTerm":"realvalue","sortField":"activityDate",...}}`.
- Had the Apex method echo back what it actually received (a temporary field on the response
  wrapper). Every single field of the nested parameter object came back null - not just the one
  field a user would notice missing (e.g. a blank search term), but also fields with "safe"
  fallback defaults (sort field, page size) that had been silently masking the same underlying
  failure the whole time. Only the fields with a forgiving default *looked* like they worked.
- The action descriptor in the captured request was `aura://ApexActionController/ACTION$execute`
  - confirming the LWC was being invoked through the legacy Aura action pipeline (this page had
    been built by clicking through Setup → Lightning App Builder → New → App Page, which produces
    an Aura-hosted container), not the native Lightning Web Runtime path.
- Ruled out (in this order, before finding the real cause): stale client-side event wiring
  (`event.target.value` vs `event.detail.value`), out-of-order async responses, browser/IndexedDB
  caching of Aura action storage, a stuck LWC component bundle cache, and a Service Worker. Each
  was independently disproved with a targeted check (fresh incognito-equivalent session + tab,
  cleared IndexedDB, confirmed no Service Worker registered, confirmed the deployed Apex class
  body was current via a random marker field) before the real cause was found.

## Root cause

Passing a complex/nested Apex wrapper class (or a `List<SomeWrapperClass>`) directly as an
`@AuraEnabled` method parameter is not reliable in this hosting context. Only some fields
populate; others silently come back null, with no exception and no client-visible error. This
matches a documented, known limitation of Aura's JSON-to-Apex-object parameter binding for
non-trivial parameter shapes - it is not specific to any one field name, and it is not a caching
issue.

## Safe fix pattern

Stop asking Aura to bind the JSON directly into a typed Apex parameter. Instead:

- **Apex**: change the method signature to take a plain `String` (e.g. `requestJson`), then
  `(MyWrapperType) JSON.deserialize(requestJson, MyWrapperType.class)` inside the method body.
  Applies the same way to a `List<Wrapper>` parameter (`(List<Wrapper>) JSON.deserialize(json,
  List<Wrapper>.class)`).
- **LWC**: `JSON.stringify(request)` before passing it to the imperative Apex call - `await
  myApexMethod({ requestJson: JSON.stringify(request) })` - instead of passing the object itself.
- Applied uniformly to every `@AuraEnabled` method on the controller that took a wrapper object or
  a list of them, not just the one where the symptom was first noticed, since the underlying
  parameter-binding gap is generic to the hosting context, not to one method or field.

## Test approach

Unit tests that call the Apex method directly with a hand-constructed parameter object cannot
catch this - they bypass the exact binding path that fails (Aura's JSON→object coercion). The
only way to catch it is an end-to-end check through the real page: type into the actual control,
capture the actual network request, and confirm the actual response reflects it. Add this as a
mandatory manual/browser verification step for any new `@AuraEnabled` method that takes a
non-primitive parameter, run at least once against the real hosting page (not just Lightning App
Builder preview or anonymous Apex) before considering the feature done.

## Prevention

Default new `@AuraEnabled` methods that take anything beyond primitive scalars to the
JSON-string-parameter pattern from the start, rather than a typed wrapper/list parameter -
especially when the target page might be Aura-hosted (built via classic Lightning App Builder
"App Page" rather than a Lightning Web Runtime-only surface). This avoids depending on Aura's
object-binding behavior at all.
