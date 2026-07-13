# Metadata Snapshot Standard

## Source of Truth

The reviewed, version-controlled Salesforce project is the engineering baseline. A production org is the current operational state and must be checked when a case depends on current configuration. Neither replaces the other.

## Snapshot Model

Retrieve affected metadata into `org-snapshots/<case-or-date>/` only. This directory is ignored by Git. Record target org, retrieval time, API version, retrieval scope, and source commit in a small local note. Diff the snapshot against the approved source before planning a change.

Do not routinely retrieve and commit an entire production org. It is slow, noisy, can contain unmanaged/package-owned components, becomes stale, and can overwrite local source. Keep a lightweight tracked inventory of confirmed component names and dates only when it is useful.

## Retrieval Rules

Use targeted metadata names, a manifest, or existing source paths. Never retrieve directly over approved source without preserving a diff and explicit approval. Do not commit customer data, debug logs, auth files, or secrets.

## After a Production Change

Retrieve or otherwise verify affected metadata, compare it to the release artifact, and update the actual Salesforce source repository through normal review.
