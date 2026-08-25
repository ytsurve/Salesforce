# Hand-escaped SOSL rejected ordinary punctuation in a user's search term

## Symptom

A list-view search box threw a hard error for a perfectly normal search term - one copied straight
out of a record's own Subject field, containing square brackets and a pipe:

```
Unable to load activities: Invalid string literal '\[Vendor\] Team x Client \| Lunch*'.
Illegal character sequence '\[' in string literal.
```

Ordinary alphanumeric terms worked, so the feature looked healthy until a user searched for a real
subject line.

## Evidence pattern

- The search was implemented as dynamic SOSL (`FIND '...' IN ALL FIELDS RETURNING ...`), chosen for
  speed: the term needed to match names on related records, and filtering on relationship fields
  (`Who.Name`/`What.Name`/`Owner.Name`) combined with an `ORDER BY` forces a join evaluated per
  activity row - measured at several seconds on a real ~194K-row Task table.
- Because dynamic SOSL has no bind-map overload, the term had to be escaped by hand. The
  implementation prefixed each SOSL reserved character with a single backslash, per the SOSL
  reserved-character rules.
- The error came from the query *parser*, before any search ran: a string literal only accepts a
  small set of escape sequences, and `\[` is not one of them.

## Root cause

Two escaping layers were conflated. Making a reserved character literal for the SOSL engine
requires a backslash *in the search text*, and getting a backslash through the query parser
requires doubling it - so the query text needs `\\[`, not `\[`. Single quotes and backslashes then
need their own distinct handling on top of that, since they interact with the parser differently.
Hand-rolling this correctly is possible but fragile, and the failure mode is a user-visible error
on innocuous input.

## Safe fix pattern

Restructure so the user's text never reaches query text at all - it only ever arrives as a bind
variable, which needs no escaping:

- Pre-resolve each related-record component of the search with bind-variable SOQL (owners, contacts,
  and each Related To object matched on its own display field - including number fields such as
  `CaseNumber`/`ContractNumber`), capped per object.
- Filter the main object on the resolved Id sets (`OwnerId IN :ids`, `WhoId IN :ids`,
  `WhatId IN :ids`) - indexed, and cheaper than the relationship join that motivated SOSL.
- Leave only the component that genuinely cannot be pre-resolved (the object's own text field, e.g.
  `Subject LIKE :pattern`) as a bound predicate, OR'd with the Id filters.
- Object and field names in the remaining dynamic SOQL come from code-side constants only, never
  from the client.

Accepted trade-off: the leading-wildcard `LIKE` on the main object is a table scan rather than an
index seek, so a search costs a second or two at this row count instead of being index-fast. That
was the right trade for removing a class of user-visible error; revisit only if it measurably
bothers users.

## Test approach

Add a regression test that stores a record whose text field literally contains reserved characters
(`[`, `]`, `|`) and asserts that searching that exact string *returns that record* - not merely that
it does not throw. Asserting only "no exception" passes trivially against an empty result and would
not have caught a still-broken search.

## Prevention

Never concatenate user-supplied text into dynamic SOQL or SOSL. If the search index is genuinely
required for performance, isolate the escaping in one helper with tests covering `[ ] | ' \ * ? :`
and verify it end-to-end through the real UI, rather than escaping inline at the call site.
