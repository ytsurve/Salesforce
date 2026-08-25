# Apex test passed in the evening and failed the next morning: local vs GMT midnight in an assertion

## Symptom

A sort-order assertion in an Apex test suite passed on one deployment and failed on the next, with
no change to the class under test in between - only unrelated markup and CSS had changed:

```
System.AssertException: Assertion Failed: Rows should be ordered most-recent-first by default
```

## Evidence pattern

- The list being asserted merges two objects with different temporal types: one carries a
  date-only field, the other a datetime. To compare them in one ordering, the production code
  places each date-only value at **GMT** midnight.
- The test rebuilt those same values from the response in order to check the ordering - but used
  `Datetime.newInstance(...)`, i.e. **local** midnight, shifting them by the running user's offset
  (+5:30 here).
- Test data was created relative to "now" (`Date.today().addDays(i)` alongside
  `Datetime.now().addDays(i)`), so whether a date-only row and a same-day datetime row compared
  equal, before, or after depended on the time of day the suite happened to run. Evening: passed.
  Next morning: failed.

## Root cause

The assertion reconstructed a temporal value using a different timezone basis than the code under
test, so the test's notion of the correct order diverged from the production ordering for part of
each day. The defect was entirely in the test; the shipped behaviour was correct throughout.

## Safe fix pattern

Mirror the code under test exactly - `Datetime.newInstanceGmt(...)` where production uses GMT
midnight - and say so in a comment at the call site, since the two method names differ by three
characters and the wrong one is not obviously wrong when reading.

## Test approach

A time-of-day-dependent test cannot be trusted to fail when it is wrong. Prefer assertions that do
not need the value reconstructed at all: assert on an explicit expected sequence of record Ids from
fixed, non-relative test data. Where reconstruction is unavoidable, keep the conversion in one
helper shared with, or mirrored from, production.

## Prevention

Two habits, both cheap:

- Build temporal test data from fixed instants rather than `Date.today()` / `Datetime.now()`, so a
  suite behaves identically at 09:00 and 21:00.
- Treat any `Datetime.newInstance` / `newInstanceGmt` / `valueOf` / `valueOfGmt` choice inside a
  test as a decision to check against the production code path, not a detail to pick by feel. A
  suite that only fails during part of the day reads as "flaky infrastructure" and erodes trust in
  every other assertion around it.
