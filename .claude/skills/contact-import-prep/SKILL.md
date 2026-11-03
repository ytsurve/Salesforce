---
name: contact-import-prep
description: Turn a contact list (Google Sheet link, .xlsx or .csv) into a Salesforce Contact dataload file for production, using read-only SOQL to resolve AccountId, OwnerId and RecordTypeId. Use when the user shares a contact spreadsheet and asks for an import, dataload or "proper API names" sheet. Never loads data.
---

# Contact Import Prep

Builds a Contact dataload CSV. It never inserts or updates Contacts. Read `docs/PRODUCTION_SAFETY_STANDARD.md`.

## Approval Boundary

- Invoking this skill with a sheet is the user's request for **read-only** SOQL in `prod` for that sheet only: Account, Contact, User, RecordType, describe and UI API picklist reads. Nothing else runs in prod.
- Creating a missing Account is a separate change. Show the exact record (fields, owner, record type, automation that fires, rollback), wait for an explicit yes per request, re-check duplicates right before insert, create one, verify it, then the rest.
- Never load the Contacts. The user runs the import.
- Keep source files and output in the scratchpad, never in this repository (customer data).

## Target

Confirm `sf org display -o prod` returns org `00D5Y0000024Y9XUAU` before any query. Run `sf data query` from PowerShell; Git Bash breaks its quoting. Escape `'` in SOQL literals as `\'`.

## Read the Source

1. Google Sheet: Drive `download_file_content` with `text/csv` (first tab) or `.xlsx` (all tabs). Large results are saved to a file; parse that file. If the result comes back inline, use `read_file_content` for a sample and decode the rest; confirm the row count matches the sheet's table range.
2. Local file: copy into its own scratchpad folder and read it with `python -I`.
3. Report: tabs, row count, columns, blank or odd cells (two emails in one cell keeps the first; flag it), duplicate emails within the file, and rows that look like tests (for example `@samba.tv` emails).

## Map Columns to API Names

| Source meaning | Contact field |
|---|---|
| First / Last name | `FirstName`, `LastName` (required) |
| Email, Title | `Email`, `Title` |
| Account / Agency | `AccountId` (lookup, resolved below) |
| Source | `LeadSource` (label "Deal Source") |
| LinkedIn URL | `LinkedIn_URL__c` (not `TSPC__LinkedInUrl__c`, which is unused) |

Leave out columns the user excludes and columns with no Contact field (for example client brand lists or outreach status). Name each one you dropped.

## Resolve AccountId

1. Exact name: `SELECT Id, Name, RecordType.DeveloperName, OwnerId, Owner.Name, Owner.IsActive, Website FROM Account WHERE Name IN (...)`.
2. No exact match: search `Name LIKE` and `Website` for the brand and email domain.
3. Several candidates: pick the account that already holds the most Contacts with the same email domain (`GROUP BY AccountId` on `Email LIKE '%@domain'`). Prefer evidence over name similarity; never guess.
4. No account: leave `AccountId`, `OwnerId` and `RecordTypeId` blank, write `NO ACCOUNT IN SALESFORCE` in the reference column, and offer account creation.
5. List every non-exact match with the alternatives you rejected.

## Inherit Owner and Record Type from the Account

- `OwnerId` = the matched Account's `OwnerId`. If that owner is inactive, flag the row. If the sheet has its own owner column, show where it differs from the account owner and ask which wins; never override silently.
- `RecordTypeId` = the Contact record type with the same DeveloperName as the Account's record type. Re-read Contact `recordTypeInfos` each run. Last verified Contact Ids: Advertiser `0125Y000001mTFQQA2`, Agency `0125Y000001mTFVQA2`, Platform_Publisher `0125Y000001mTFaQAM`, Strategic_Partner `012VU000001QKIfYAO`.
- Flag accounts whose record type looks wrong for the company (for example an agency on an Advertiser account). Keep the account's type and tell the user.

## LeadSource

Read active values per record type from `/ui-api/object-info/Contact/picklist-values/<rtId>/LeadSource`. Use exact matches as they are. Map `LinkedIn` to `LinkedIn Sales Navigator`. Map other values with no match (MediaRadar, events, "Salesforce", org charts) to `Other` and list them. Leave blank sources blank.

## Existing Contacts

Query `Contact WHERE Email IN (...)` in chunks of 150. For each match, put its Id in `Existing Contact Id (already in Salesforce)` and compare its current Account and Owner with the sheet. Tell the user to remove those rows; never plan updates to them without a separate request.

## Output

- CSV in the scratchpad with import columns first: `FirstName, LastName, Email, Title, AccountId, LeadSource, [LinkedIn_URL__c], OwnerId, RecordTypeId`. Then reference columns marked `(reference)` (account name, owner name, source account) and `Existing Contact Id`. Tell the user not to map reference columns.
- Send it with `SendUserFile`. If the old file is locked (open in Excel), write a `_v2` file instead of overwriting.
- No Google Sheets editor connector: say so and give the CSV, which the user imports with File > Import > Upload > Insert new sheet(s), with "Convert text to numbers, dates, and formulas" unticked.

## Account Creation (only on explicit approval)

Account insert in prod needs: `Name`, `Website` (validation rule), `Account_Geo__c` and `ISO3_Code__c` (required on create for non-admins; ask when location is unverified), `OwnerId`, Account `RecordTypeId` (Advertiser `0125Y000001mSeuQAE`, Agency `0125Y000001mSfEQAU`, Platform_Publisher `012VU000000R7rpYAC`). `Account_Assignment_Flow` only fires for creator `0055Y00000GcSrrQAF`, so owner stays as set. The territory flow may leave `Territory__c` blank for some owner verticals. Rollback is deleting the new Id while nothing is attached. After creation, fill the Ids into the CSV.

## Report

Rows in and out, accounts matched exactly versus by evidence, rows with no account, existing contacts, dropped columns, source-value mapping, owner and record-type counts, and anything you could not verify.
