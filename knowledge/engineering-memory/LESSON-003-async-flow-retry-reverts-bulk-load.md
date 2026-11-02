# LESSON-003 — A failed async flow path can retry later and revert a bulk load

Sanitized. Case detail (record Ids, opportunity names, load files, retrieved flow and Apex source,
debug logs) is held locally under `org-snapshots/2026-11-02-olis-gross-reset/` and the session
scratchpad, and is not reproduced here.

## Context

A bulk update set Actual Gross Amount, TAC, Billing Status = Approved and Cost Approval Status =
Approved on 106 Opportunity Product Schedule (`OpportunityLineItemSchedule__c`) records in
production. The load tool reported every row as succeeded, and a read-only check right after the
load matched all 106 rows to the file.

Three days later, 50 of the rows showed Billing Status = Pending and a blank Actual Gross Amount.
Field history recorded the change under the loading user's own name, about 17–20 minutes after the
load. The user had run no second update.

## Root cause

The record-triggered flow `Actual_Amount_Updated_for_Audience` starts when `Actual_Amount__c`
changes on a non-Data, auto-scheduled line item. It has one asynchronous path (`AsyncAfterCommit`)
that calls the subflow `Assign_Forecasted_based_on_Actuals_Subflow_1`. That subflow:

1. Reads **all** schedules on the line item with automatically stored fields, including
   `Billing_Status__c` and `Actual_Amount__c`.
2. Treats every month that is not Approved as "pending" and re-spreads the remaining line-item
   total over them by days. Any negative amount becomes 0.
3. Updates the pending months by saving the **stored record collection**. That writes every
   stored field, not only `Forecasted_Amount__c`.

Here is how that reverted the load:

- The load ran in batches of 5. The async interview started by one batch read sibling rows on the
  same line item before *their* batch had committed, so those rows were still Pending and blank.
  The interview stored them as "pending".
- Its update would have written Pending and a blank Gross over rows that had since been approved.
  Blanking Gross meets the flow's own entry condition, so the platform refused the save:
  `MAX_DEPTH_IN_FLOW_EXECUTION: An after-commit path cannot reschedule itself`. The user received
  one flow-error email per failed interview.
- The platform did not discard the failed interviews. It **paused them at `Try_Again`**, keeping
  their stored variables.
- About 17–20 minutes later the paused interviews retried automatically, as the loading user. This
  time the save succeeded and wrote the stale Pending and blank values back. TAC and Cost Status
  survived because the subflow does not store them.

## Evidence pattern

These steps settled it, in this order:

1. **Field history shape.** The reset changed only some fields (Billing Status and Gross, not TAC
   or Cost Status) back to their exact pre-load values. That points to a stale write-back of a
   partial record, not to a person or a rule.
2. **Eliminate the obvious sources first, read-only.** In this case all of these were clean:
   - Login history and OAuth token last-used dates for the user.
   - The Setup Audit Trail (no Login-As).
   - Local CLI logs and Claude session transcripts for the time window.
   - All Apex, triggers and flows grepped for writes to the field.
   - Workflow rules, scheduler mapping metadata, DLRS rollups, and LWC, Aura and Visualforce
     components.
3. **Correlate with async jobs.** A batch class ran at exactly the reset times. It was downstream
   (split recalculation as Automated Process) and a distraction, not the cause.
4. **Capture a live repeat with a trace flag** on the user, then redo the load. "Application" logs
   (async paths) appeared between the "Api" logs. Their first code unit is the record-triggered
   flow, and they show the subflow's Get, Loop and Update elements.
5. **The flow-error email shows the stored payload.** The `Update_Pending_Schedule_Forecasts`
   variable values included `"Actual_Amount__c":null` and `"Billing_Status__c":"Pending"` for rows
   that were Approved in the database.
6. **Query `FlowInterview`.** Interviews of the flow had `InterviewStatus = Paused` and
   `CurrentElement = Try_Again`, created seconds after the load. The interviews from the earlier
   incident had already resumed, and their records were gone.

## Fix and containment

- **Immediate containment, done by the user:** delete the paused `Try_Again` interviews (Setup →
  Paused and Failed Flow Interviews) before the retry fires. After deletion, all 50 rows stayed
  Approved with Gross intact and no further field-history changes.
- **What deletion leaves undone:** the forecast re-spread on future Pending months of the affected
  line items. Here 9 Pending months on 2 line items kept old forecasts that the flow would have
  set to 0: $602.44 in total, which feeds Adjusted Gross Forecast and the rollups built on it. The
  user chose to leave them.
- **Permanent fix, not yet built:** make `Update_Pending_Schedule_Forecasts` write only `Id` and
  `Forecasted_Amount__c`, for example by building new record variables with only those two fields,
  or by using an update with field assignments and filter conditions. Develop and test it in a
  sandbox. Re-check the async-path recursion behavior after the change.

## Trade-offs

- Deleting the paused interviews protects the loaded values, but leaves some forecasts stale.
  Letting them run would have proven the cause in a debug log, but would have reverted rows a
  second time. The cause was already proven, so containment won.
- Loading one line item's rows in a single batch would cut down the stale reads, but it does not
  remove them. Async interviews can still overlap later saves. Only the narrow update fixes it.

## Test approach for the fix

- In a sandbox, bulk-load Gross and Approved status across several months of one line item, split
  over several batches of 5.
- Assert that the subflow sends no Billing Status or Gross in its update payload (debug log), that
  no `Try_Again` paused interviews appear, and that field history shows no reverts 30 minutes later.
- Assert that the pending-month forecasts still equal the re-spread formula.

## Future prevention

- After any bulk load that changes Gross or Billing Status on schedules, check `FlowInterview` for
  paused `Try_Again` interviews of this flow within a few minutes. Expect "Assign Forecasted based
  on Actuals Subflow" error emails as the signal.
- A check right after a load is not the final check. Re-verify more than 20 minutes after the load
  when async flow paths exist on the object.
- When field history shows a change "by" a user who denies it, and there are no logins, tokens or
  Login-As, look for async flow paths, paused or retried interviews and queueables running as that
  user before suspecting a person.

## Production changes made during the investigation

- A trace flag on the investigating user (auto-expiring) and a debug level
  `OLIS_Gross_Reset_Debug`, created on the user's explicit request. The debug level remains until
  someone removes it.
- Everything else was read-only: queries, describes and metadata retrieves.
