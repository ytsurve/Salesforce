/**
 * Server-side support for the c-activities-list LWC: merges Task and Event records into a
 * single sorted, filtered, paged result set. Task and Event cannot be combined in one SOQL
 * query (no cross-object UNION in SOQL), so each object is queried independently with an
 * equivalent WHERE/ORDER BY translation, then merged and re-sorted in Apex before paging.
 */
public with sharing class ActivitiesListController {

    private static final Integer DEFAULT_PAGE_SIZE = 50;
    private static final Integer MAX_PAGE_SIZE = 100;
    // Ceiling on how many related records (per object) one search term may resolve to. A term
    // broad enough to match more than this is not a useful filter anyway; matches beyond the cap
    // are not represented in the results.
    private static final Integer MATCH_CAP = 500;

    // The objects the search resolves "Related To" (WhatId) and "Name" (WhoId) against, mapped to
    // the field holding their display text. Case and Contract are matched on their number rather
    // than a Name field, which they do not have - and those numbers are exactly what the Related
    // To column shows for them. Name is Contact-only, matching the lookup editor's own scope.
    private static final Map<String, String> WHAT_SEARCH_FIELD_BY_OBJECT = new Map<String, String>{
        'Account' => 'Name',
        'Opportunity' => 'Name',
        'Campaign' => 'Name',
        'Case' => 'CaseNumber',
        'Contract' => 'ContractNumber'
    };
    private static final Map<String, String> WHO_SEARCH_FIELD_BY_OBJECT = new Map<String, String>{
        'Contact' => 'Name'
    };

    // Backed by a Custom Label (not hardcoded here) so the Id can be corrected per-org without a
    // code deploy - this user is a Service Account that may not exist in every sandbox (e.g. it's
    // absent from this org's fullcopy), in which case the Backstory view legitimately returns zero
    // rows rather than erroring.
    private static final Id BACKSTORY_INTEGRATION_USER_ID = Id.valueOf(Label.Activities_Backstory_Integration_User_Id);

    // ------------------------------------------------------------------------------------
    // Wrapper types
    // ------------------------------------------------------------------------------------

    public class QueryRequest {
        @AuraEnabled public String searchTerm;
        @AuraEnabled public String view;
        @AuraEnabled public String sortField;
        @AuraEnabled public String sortDirection;
        @AuraEnabled public Integer pageOffset;
        @AuraEnabled public Integer pageSize;
    }

    public class ActivitiesResult {
        @AuraEnabled public List<ActivityRow> rows = new List<ActivityRow>();
        @AuraEnabled public Boolean hasMore = false;
        // lightning-datatable's "editable" is a column-level (not per-row) property, so these
        // reflect whether the current user could edit the field on AT LEAST one of Task/Event.
        // Per-row FLS/sharing is still enforced via ActivityRow.subjectEditable/dateEditable
        // (used to gate row actions and as a client-side pre-save guard) and, ultimately, by
        // the DML layer itself when a save is attempted.
        @AuraEnabled public Boolean subjectColumnEditable = false;
        @AuraEnabled public Boolean dateColumnEditable = false;
        @AuraEnabled public Boolean relatedToColumnEditable = false;
        @AuraEnabled public Boolean nameColumnEditable = false;
        @AuraEnabled public Boolean assignedToColumnEditable = false;
    }

    public class ActivityRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String activityType;
        @AuraEnabled public String activityIconName;
        @AuraEnabled public String subject;
        @AuraEnabled public Boolean subjectEditable = false;
        @AuraEnabled public Id relatedToId;
        @AuraEnabled public String relatedToName;
        @AuraEnabled public String relatedToObjectApiName;
        @AuraEnabled public Id nameId;
        @AuraEnabled public String name;
        @AuraEnabled public String nameObjectApiName;
        @AuraEnabled public Id assignedToId;
        @AuraEnabled public String assignedToName;
        @AuraEnabled public String assignedToObjectApiName;
        @AuraEnabled public String activityDateDisplay;
        @AuraEnabled public String activityDateEditValue;
        @AuraEnabled public Boolean dateOnly = true;
        @AuraEnabled public Boolean dateEditable = false;
        @AuraEnabled public Boolean relatedToEditable = false;
        @AuraEnabled public Boolean nameEditable = false;
        @AuraEnabled public Boolean assignedToEditable = false;
        @AuraEnabled public Boolean deletable = false;
        @AuraEnabled public Boolean editableRow = false;

        // Not exposed to the client; used only for in-memory merge sorting.
        public transient Datetime sortableDateTime;
    }

    public class ActivityDraft {
        @AuraEnabled public String recordId;
        @AuraEnabled public String activityType;
        @AuraEnabled public Map<String, Object> changedFields;
    }

    public class SaveResult {
        @AuraEnabled public Boolean success = true;
        @AuraEnabled public List<String> errors = new List<String>();
    }

    // ------------------------------------------------------------------------------------
    // Read
    // ------------------------------------------------------------------------------------

    /**
     * Resolves a lookup's display text for the inline-edit live preview. The datatable captures
     * the newly-picked Id immediately, but the Related To / Name / Assigned To columns DISPLAY a
     * name field, not the Id field being edited - so lightning-datatable has no way to recompute
     * the visible text on its own until the row is saved and reloaded. The client calls this the
     * moment a lookup draft is committed so the cell can show the real label right away.
     *
     * The object type is derived from the Id itself rather than passed in: WhatId is polymorphic,
     * and the Id already carries its type. The display field comes from the object describe's own
     * name field (isNameField) rather than a hardcoded 'Name' - Case and Contract, both valid
     * WhatId targets, use CaseNumber/ContractNumber instead.
     *
     * AccessLevel.USER_MODE enforces FLS and sharing on the read; a record the user cannot see
     * resolves to null and the client leaves the existing text alone rather than blanking it.
     */
    @AuraEnabled(cacheable=true)
    public static String getLookupDisplayName(Id recordId) {
        if (recordId == null) {
            return null;
        }
        try {
            Schema.DescribeSObjectResult objectDescribe = recordId.getSObjectType().getDescribe();
            String displayField = null;
            for (Schema.SObjectField field : objectDescribe.fields.getMap().values()) {
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                if (fieldDescribe.isNameField() && fieldDescribe.isAccessible()) {
                    displayField = fieldDescribe.getName();
                    break;
                }
            }
            if (displayField == null) {
                return null;
            }
            String soql = 'SELECT ' + displayField + ' FROM ' + objectDescribe.getName() + ' WHERE Id = :recordId';
            List<SObject> records = Database.queryWithBinds(
                soql, new Map<String, Object>{ 'recordId' => recordId }, AccessLevel.USER_MODE
            );
            return records.isEmpty() ? null : String.valueOf(records[0].get(displayField));
        } catch (Exception ex) {
            return null;
        }
    }

    // Takes the request pre-serialized to JSON rather than as a QueryRequest parameter directly:
    // passing a complex nested object straight through as an @AuraEnabled parameter is unreliable
    // when this component is hosted on an Aura-based page (dispatched via
    // aura://ApexActionController rather than the native Lightning Web Runtime path) - confirmed
    // by direct inspection that every field of such a parameter arrived null server-side despite
    // the client sending correct values. Deserializing a plain JSON string sidesteps that
    // platform-level parameter-binding gap entirely.
    @AuraEnabled
    public static ActivitiesResult getActivities(String requestJson) {
        try {
            QueryRequest request = String.isBlank(requestJson)
                ? new QueryRequest()
                : (QueryRequest) JSON.deserialize(requestJson, QueryRequest.class);
            Integer pageSize = normalizePageSize(request.pageSize);
            Integer pageOffset = (request.pageOffset == null || request.pageOffset < 0) ? 0 : request.pageOffset;
            String sortField = String.isBlank(request.sortField) ? 'activityDate' : request.sortField;
            // Most-recent-first by default - matches this being an activity feed, not a
            // alphabetical record list.
            String sortDirection = ('asc'.equalsIgnoreCase(request.sortDirection)) ? 'ASC' : 'DESC';
            Integer fetchLimit = pageOffset + pageSize + 1;

            FilterPlan plan = String.isNotBlank(request.searchTerm)
                ? buildSearchPlan(request.searchTerm)
                : noFilterPlan();
            plan = applyViewFilter(plan, request.view);

            List<ActivityRow> merged = new List<ActivityRow>();
            if (Schema.SObjectType.Task.isAccessible() && plan.taskClause != FilterPlan.ALWAYS_FALSE) {
                merged.addAll(queryTasks(plan, sortField, sortDirection, fetchLimit));
            }
            if (Schema.SObjectType.Event.isAccessible() && plan.eventClause != FilterPlan.ALWAYS_FALSE) {
                merged.addAll(queryEvents(plan, sortField, sortDirection, fetchLimit));
            }

            merged.sort(new ActivityRowComparator(sortField, sortDirection));

            ActivitiesResult result = new ActivitiesResult();
            if (pageOffset < merged.size()) {
                Integer endExclusive = Math.min(merged.size(), pageOffset + pageSize);
                result.rows = new List<ActivityRow>();
                for (Integer i = pageOffset; i < endExclusive; i++) {
                    result.rows.add(merged[i]);
                }
            }
            result.hasMore = merged.size() > pageOffset + pageSize;
            enrichAccessFlags(result.rows);
            result.subjectColumnEditable = isFieldEditableOnEitherObject('Subject', 'Subject');
            result.dateColumnEditable = isFieldEditableOnEitherObject('ActivityDate', 'StartDateTime');
            result.relatedToColumnEditable = isFieldEditableOnEitherObject('WhatId', 'WhatId');
            result.nameColumnEditable = isFieldEditableOnEitherObject('WhoId', 'WhoId');
            result.assignedToColumnEditable = isFieldEditableOnEitherObject('OwnerId', 'OwnerId');
            return result;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load activities: ' + ex.getMessage());
        }
    }

    /**
     * ANDs the selected view's fixed predicates onto whatever clause search already produced.
     * These are preset views, not a general-purpose filter:
     *
     *   all         - everything the running user can see.
     *   backstory   - created by the Backstory Integration User, whoever it is assigned to.
     *   my          - created by the running user.
     *   myBackstory - created by the Backstory Integration User AND assigned to the running user.
     *
     * Note the deliberate asymmetry between "my" (created by me) and "my backstory" (created by
     * the integration, assigned to me): an integration-created activity is never created by the
     * person who owns it, so keying the Backstory view off CreatedById alone would make "mine"
     * mean nothing. Ownership is what makes it theirs.
     */
    private static FilterPlan applyViewFilter(FilterPlan plan, String view) {
        Boolean isBackstory = 'backstory'.equalsIgnoreCase(view);
        Boolean isMy = 'my'.equalsIgnoreCase(view);
        Boolean isMyBackstory = 'myBackstory'.equalsIgnoreCase(view);

        List<String> predicates = new List<String>();
        if (isBackstory || isMyBackstory) {
            predicates.add('CreatedById = :backstoryUserId');
            plan.binds.put('backstoryUserId', BACKSTORY_INTEGRATION_USER_ID);
        }
        if (isMy) {
            predicates.add('CreatedById = :currentUserId');
        }
        if (isMyBackstory) {
            predicates.add('OwnerId = :currentUserId');
        }
        if (isMy || isMyBackstory) {
            plan.binds.put('currentUserId', UserInfo.getUserId());
        }
        if (predicates.isEmpty()) {
            return plan;
        }

        String viewClause = String.join(predicates, ' AND ');
        if (plan.taskClause != FilterPlan.ALWAYS_FALSE) {
            plan.taskClause = '(' + plan.taskClause + ') AND ' + viewClause;
        }
        if (plan.eventClause != FilterPlan.ALWAYS_FALSE) {
            plan.eventClause = '(' + plan.eventClause + ') AND ' + viewClause;
        }
        return plan;
    }

    private static Integer normalizePageSize(Integer requested) {
        if (requested == null || requested <= 0) {
            return DEFAULT_PAGE_SIZE;
        }
        return Math.min(requested, MAX_PAGE_SIZE);
    }

    // No ad-hoc filters exist any more (the Filters UI/engine was removed) - every row on both
    // objects is in scope unless the search box or the Backstory view narrows it further.
    private static FilterPlan noFilterPlan() {
        FilterPlan plan = new FilterPlan();
        plan.taskClause = 'Id != null';
        plan.eventClause = 'Id != null';
        return plan;
    }

    /**
     * Searches the four text columns the list actually shows - Subject, Related To, Name and
     * Assigned To - across both Task and Event.
     *
     * Only Subject lives on the activity itself. The other three are names on related records, so
     * rather than filtering on Who.Name/What.Name/Owner.Name (a relationship join evaluated for
     * every activity row, which combined with an ORDER BY took seconds on this org's real Task
     * volume), the term is first resolved to matching related-record Ids and the activity-side
     * filter becomes an indexed 'WhoId/WhatId/OwnerId IN :ids'.
     *
     * The term only ever reaches the database as a bind variable, never concatenated into query
     * text. An earlier SOSL implementation had to hand-escape the term's reserved characters and
     * rejected ordinary subjects such as "[Gong] Samba x WPP | Lunch" outright; there is nothing
     * to escape here. Object and field names in the dynamic SOQL below come only from the
     * WHAT_/WHO_SEARCH_FIELD_BY_OBJECT constants, never from the client.
     *
     * Queues are included in the owner lookup because Task.OwnerId may be a Group, and such rows
     * show the queue's name in Assigned To - searching that name should find them.
     */
    private static FilterPlan buildSearchPlan(String searchTerm) {
        FilterPlan plan = new FilterPlan();
        String pattern = '%' + searchTerm.trim() + '%';

        Set<Id> ownerIds = new Set<Id>();
        for (User owner : [SELECT Id FROM User WHERE Name LIKE :pattern LIMIT :MATCH_CAP]) {
            ownerIds.add(owner.Id);
        }
        for (Group queue : [SELECT Id FROM Group WHERE Type = 'Queue' AND Name LIKE :pattern LIMIT :MATCH_CAP]) {
            ownerIds.add(queue.Id);
        }

        Set<Id> whatIds = idsMatchingName(WHAT_SEARCH_FIELD_BY_OBJECT, pattern);
        Set<Id> whoIds = idsMatchingName(WHO_SEARCH_FIELD_BY_OBJECT, pattern);

        // Subject is the one term component that cannot be pre-resolved to Ids, so it stays a LIKE
        // on the activity itself and is OR'd together with the resolved-Id filters.
        List<String> orClauses = new List<String>{ 'Subject LIKE :pattern' };
        plan.binds.put('pattern', pattern);
        if (!ownerIds.isEmpty()) {
            orClauses.add('OwnerId IN :ownerIds');
            plan.binds.put('ownerIds', ownerIds);
        }
        if (!whoIds.isEmpty()) {
            orClauses.add('WhoId IN :whoIds');
            plan.binds.put('whoIds', whoIds);
        }
        if (!whatIds.isEmpty()) {
            orClauses.add('WhatId IN :whatIds');
            plan.binds.put('whatIds', whatIds);
        }

        String clause = '(' + String.join(orClauses, ' OR ') + ')';
        plan.taskClause = clause;
        plan.eventClause = clause;
        return plan;
    }

    private static Set<Id> idsMatchingName(Map<String, String> searchFieldByObject, String pattern) {
        Set<Id> ids = new Set<Id>();
        for (String objectApiName : searchFieldByObject.keySet()) {
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
            // An org may not have every one of these objects enabled, and the running user may not
            // be able to read those it does - skip rather than failing the whole search.
            if (objectType == null || !objectType.getDescribe().isAccessible()) {
                continue;
            }
            String soql = 'SELECT Id FROM ' + objectApiName
                + ' WHERE ' + searchFieldByObject.get(objectApiName) + ' LIKE :pattern'
                + ' LIMIT ' + MATCH_CAP;
            for (SObject record : Database.queryWithBinds(
                soql, new Map<String, Object>{ 'pattern' => pattern }, AccessLevel.USER_MODE
            )) {
                ids.add(record.Id);
            }
        }
        return ids;
    }

    private static List<ActivityRow> queryTasks(FilterPlan plan, String sortField, String sortDirection, Integer fetchLimit) {
        String orderByField = ActivityFieldMap.taskSortColumn(sortField);
        String soql = 'SELECT Id, Subject, ActivityDate, Status, Priority, WhoId, Who.Name, WhatId, What.Name, '
            + 'OwnerId, Owner.Name FROM Task WHERE ' + plan.taskClause
            + ' ORDER BY ' + orderByField + ' ' + sortDirection + ' NULLS LAST, Id ASC'
            + ' LIMIT ' + fetchLimit;
        List<Task> tasks = (List<Task>) Database.queryWithBinds(soql, plan.binds, AccessLevel.USER_MODE);
        List<ActivityRow> rows = new List<ActivityRow>();
        for (Task t : tasks) {
            ActivityRow row = new ActivityRow();
            row.recordId = t.Id;
            row.activityType = 'Task';
            row.activityIconName = 'standard:task';
            row.subject = t.Subject;
            row.relatedToId = t.WhatId;
            row.relatedToName = t.WhatId != null ? t.What.Name : null;
            row.relatedToObjectApiName = objectApiNameOf(t.WhatId);
            row.nameId = t.WhoId;
            row.name = t.WhoId != null ? t.Who.Name : null;
            row.nameObjectApiName = objectApiNameOf(t.WhoId);
            row.assignedToId = t.OwnerId;
            row.assignedToName = t.OwnerId != null ? t.Owner.Name : null;
            row.assignedToObjectApiName = objectApiNameOf(t.OwnerId);
            row.dateOnly = true;
            if (t.ActivityDate != null) {
                row.activityDateDisplay = t.ActivityDate.format();
                row.activityDateEditValue = String.valueOf(t.ActivityDate);
                row.sortableDateTime = Datetime.newInstanceGmt(t.ActivityDate, Time.newInstance(0, 0, 0, 0));
            }
            rows.add(row);
        }
        return rows;
    }

    private static List<ActivityRow> queryEvents(FilterPlan plan, String sortField, String sortDirection, Integer fetchLimit) {
        String orderByField = ActivityFieldMap.eventSortColumn(sortField);
        String soql = 'SELECT Id, Subject, StartDateTime, EndDateTime, WhoId, Who.Name, WhatId, What.Name, '
            + 'OwnerId, Owner.Name FROM Event WHERE ' + plan.eventClause
            + ' ORDER BY ' + orderByField + ' ' + sortDirection + ' NULLS LAST, Id ASC'
            + ' LIMIT ' + fetchLimit;
        List<Event> events = (List<Event>) Database.queryWithBinds(soql, plan.binds, AccessLevel.USER_MODE);
        List<ActivityRow> rows = new List<ActivityRow>();
        for (Event e : events) {
            ActivityRow row = new ActivityRow();
            row.recordId = e.Id;
            row.activityType = 'Event';
            row.activityIconName = 'standard:event';
            row.subject = e.Subject;
            row.relatedToId = e.WhatId;
            row.relatedToName = e.WhatId != null ? e.What.Name : null;
            row.relatedToObjectApiName = objectApiNameOf(e.WhatId);
            row.nameId = e.WhoId;
            row.name = e.WhoId != null ? e.Who.Name : null;
            row.nameObjectApiName = objectApiNameOf(e.WhoId);
            row.assignedToId = e.OwnerId;
            row.assignedToName = e.OwnerId != null ? e.Owner.Name : null;
            row.assignedToObjectApiName = objectApiNameOf(e.OwnerId);
            row.dateOnly = false;
            if (e.StartDateTime != null) {
                row.activityDateDisplay = e.StartDateTime.format();
                row.activityDateEditValue = e.StartDateTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
                row.sortableDateTime = e.StartDateTime;
            }
            rows.add(row);
        }
        return rows;
    }

    private static Boolean isFieldEditableOnEitherObject(String taskField, String eventField) {
        Boolean taskOk = Schema.SObjectType.Task.isUpdateable()
            && Schema.SObjectType.Task.fields.getMap().get(taskField).getDescribe().isUpdateable();
        Boolean eventOk = Schema.SObjectType.Event.isUpdateable()
            && Schema.SObjectType.Event.fields.getMap().get(eventField).getDescribe().isUpdateable();
        return taskOk || eventOk;
    }

    private static String objectApiNameOf(Id recordId) {
        if (recordId == null) {
            return null;
        }
        return recordId.getSObjectType().getDescribe().getName();
    }

    private static void enrichAccessFlags(List<ActivityRow> rows) {
        if (rows.isEmpty()) {
            return;
        }
        Set<Id> ids = new Set<Id>();
        for (ActivityRow r : rows) {
            ids.add(r.recordId);
        }
        Map<Id, UserRecordAccess> accessByRecord = new Map<Id, UserRecordAccess>();
        for (UserRecordAccess ura : [
            SELECT RecordId, HasEditAccess, HasDeleteAccess
            FROM UserRecordAccess
            WHERE UserId = :UserInfo.getUserId() AND RecordId IN :ids
        ]) {
            accessByRecord.put(ura.RecordId, ura);
        }

        Boolean taskSubjectFls = Schema.SObjectType.Task.fields.Subject.isUpdateable();
        Boolean taskDateFls = Schema.SObjectType.Task.fields.ActivityDate.isUpdateable();
        Boolean taskWhatFls = Schema.SObjectType.Task.fields.WhatId.isUpdateable();
        Boolean taskWhoFls = Schema.SObjectType.Task.fields.WhoId.isUpdateable();
        Boolean taskOwnerFls = Schema.SObjectType.Task.fields.OwnerId.isUpdateable();
        Boolean taskDeletableObj = Schema.SObjectType.Task.isDeletable();
        Boolean eventSubjectFls = Schema.SObjectType.Event.fields.Subject.isUpdateable();
        Boolean eventDateFls = Schema.SObjectType.Event.fields.StartDateTime.isUpdateable();
        Boolean eventWhatFls = Schema.SObjectType.Event.fields.WhatId.isUpdateable();
        Boolean eventWhoFls = Schema.SObjectType.Event.fields.WhoId.isUpdateable();
        Boolean eventOwnerFls = Schema.SObjectType.Event.fields.OwnerId.isUpdateable();
        Boolean eventDeletableObj = Schema.SObjectType.Event.isDeletable();

        for (ActivityRow r : rows) {
            UserRecordAccess ura = accessByRecord.get(r.recordId);
            Boolean hasEdit = ura != null && ura.HasEditAccess;
            Boolean hasDelete = ura != null && ura.HasDeleteAccess;
            if (r.activityType == 'Task') {
                r.subjectEditable = hasEdit && taskSubjectFls;
                r.dateEditable = hasEdit && taskDateFls;
                r.relatedToEditable = hasEdit && taskWhatFls;
                r.nameEditable = hasEdit && taskWhoFls;
                r.assignedToEditable = hasEdit && taskOwnerFls;
                r.deletable = hasDelete && taskDeletableObj;
            } else {
                r.subjectEditable = hasEdit && eventSubjectFls;
                r.dateEditable = hasEdit && eventDateFls;
                r.relatedToEditable = hasEdit && eventWhatFls;
                r.nameEditable = hasEdit && eventWhoFls;
                r.assignedToEditable = hasEdit && eventOwnerFls;
                r.deletable = hasDelete && eventDeletableObj;
            }
            r.editableRow = hasEdit;
        }
    }

    private class ActivityRowComparator implements Comparator<ActivityRow> {
        private final String sortField;
        private final Integer direction;

        ActivityRowComparator(String sortField, String sortDirection) {
            this.sortField = sortField;
            this.direction = ('DESC'.equalsIgnoreCase(sortDirection)) ? -1 : 1;
        }

        public Integer compare(ActivityRow a, ActivityRow b) {
            Integer primary = comparePrimary(a, b);
            if (primary != 0) {
                return primary * direction;
            }
            return String.valueOf(a.recordId).compareTo(String.valueOf(b.recordId));
        }

        private Integer comparePrimary(ActivityRow a, ActivityRow b) {
            if (sortField == 'activityDate') {
                if (a.sortableDateTime == null && b.sortableDateTime == null) return 0;
                if (a.sortableDateTime == null) return 1;
                if (b.sortableDateTime == null) return -1;
                return a.sortableDateTime < b.sortableDateTime ? -1 : (a.sortableDateTime > b.sortableDateTime ? 1 : 0);
            }
            String valA = stringValue(a, sortField);
            String valB = stringValue(b, sortField);
            if (String.isBlank(valA) && String.isBlank(valB)) return 0;
            if (String.isBlank(valA)) return 1;
            if (String.isBlank(valB)) return -1;
            return valA.compareTo(valB);
        }

        private String stringValue(ActivityRow r, String field) {
            if (field == 'subject') return r.subject;
            if (field == 'assignedToName') return r.assignedToName;
            if (field == 'relatedToName') return r.relatedToName;
            if (field == 'name') return r.name;
            if (field == 'activityType') return r.activityType;
            return r.subject;
        }
    }

    // ------------------------------------------------------------------------------------
    // Save / Delete
    // ------------------------------------------------------------------------------------

    private static List<ActivityDraft> parseDrafts(String draftsJson) {
        List<ActivityDraft> drafts = new List<ActivityDraft>();
        if (String.isBlank(draftsJson)) {
            return drafts;
        }
        for (Object rawItem : (List<Object>) JSON.deserializeUntyped(draftsJson)) {
            Map<String, Object> rawDraft = (Map<String, Object>) rawItem;
            ActivityDraft draft = new ActivityDraft();
            draft.recordId = (String) rawDraft.get('recordId');
            draft.activityType = (String) rawDraft.get('activityType');
            draft.changedFields = (Map<String, Object>) rawDraft.get('changedFields');
            drafts.add(draft);
        }
        return drafts;
    }

    @AuraEnabled
    public static SaveResult saveActivities(String draftsJson) {
        SaveResult result = new SaveResult();
        try {
            // See getActivities for why this takes a JSON string rather than List<ActivityDraft>
            // directly - passing wrapper objects/lists straight through as @AuraEnabled parameters
            // was confirmed unreliable on this Aura-hosted page.
            // Uses deserializeUntyped + manual mapping rather than JSON.deserialize(json, Type) -
            // the typed deserializer throws "Apex Type unsupported in JSON: Object" for any class
            // containing a Map<String, Object> field, which changedFields is.
            List<ActivityDraft> drafts = parseDrafts(draftsJson);
            List<Task> tasksToUpdate = new List<Task>();
            List<Event> eventsToUpdate = new List<Event>();
            Set<Id> eventIdsNeedingShift = new Set<Id>();

            for (ActivityDraft d : drafts) {
                if (d.recordId == null || d.changedFields == null) {
                    continue;
                }
                if (d.activityType == 'Task') {
                    Task t = new Task(Id = d.recordId);
                    for (String key : d.changedFields.keySet()) {
                        applyTaskField(t, key, d.changedFields.get(key));
                    }
                    tasksToUpdate.add(t);
                } else if (d.activityType == 'Event') {
                    Event e = new Event(Id = d.recordId);
                    for (String key : d.changedFields.keySet()) {
                        applyEventField(e, key, d.changedFields.get(key));
                    }
                    eventsToUpdate.add(e);
                    if (d.changedFields.containsKey('activityDateEditValue')) {
                        eventIdsNeedingShift.add(d.recordId);
                    }
                }
            }

            if (!eventIdsNeedingShift.isEmpty()) {
                preserveEventDuration(eventsToUpdate, eventIdsNeedingShift);
            }

            if (!tasksToUpdate.isEmpty() && Schema.SObjectType.Task.isUpdateable()) {
                SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, tasksToUpdate);
                List<Database.SaveResult> saveResults = Database.update(decision.getRecords(), false);
                collectDmlErrors(saveResults, result.errors);
            }
            if (!eventsToUpdate.isEmpty() && Schema.SObjectType.Event.isUpdateable()) {
                SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, eventsToUpdate);
                List<Database.SaveResult> saveResults = Database.update(decision.getRecords(), false);
                collectDmlErrors(saveResults, result.errors);
            }
            result.success = result.errors.isEmpty();
            return result;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to save activities: ' + ex.getMessage());
        }
    }

    private static void preserveEventDuration(List<Event> eventsToUpdate, Set<Id> eventIds) {
        Map<Id, Event> currentById = new Map<Id, Event>([
            SELECT Id, StartDateTime, EndDateTime FROM Event WHERE Id IN :eventIds WITH USER_MODE
        ]);
        for (Event e : eventsToUpdate) {
            Event current = currentById.get(e.Id);
            if (current == null || current.StartDateTime == null || current.EndDateTime == null || e.StartDateTime == null) {
                continue;
            }
            Long durationMs = current.EndDateTime.getTime() - current.StartDateTime.getTime();
            e.EndDateTime = e.StartDateTime.addSeconds((Integer) (durationMs / 1000));
        }
    }

    private static void applyTaskField(Task t, String logicalField, Object value) {
        if (logicalField == 'subject') {
            t.Subject = value == null ? null : String.valueOf(value);
        } else if (logicalField == 'activityDateEditValue') {
            t.ActivityDate = value == null ? null : parseIsoDate(String.valueOf(value));
        } else if (logicalField == 'relatedToId') {
            t.WhatId = value == null ? null : (Id) String.valueOf(value);
        } else if (logicalField == 'nameId') {
            t.WhoId = value == null ? null : (Id) String.valueOf(value);
        } else if (logicalField == 'assignedToId') {
            t.OwnerId = value == null ? null : (Id) String.valueOf(value);
        }
    }

    private static void applyEventField(Event e, String logicalField, Object value) {
        if (logicalField == 'subject') {
            e.Subject = value == null ? null : String.valueOf(value);
        } else if (logicalField == 'activityDateEditValue') {
            e.StartDateTime = value == null ? null : parseIsoDateTime(String.valueOf(value));
        } else if (logicalField == 'relatedToId') {
            e.WhatId = value == null ? null : (Id) String.valueOf(value);
        } else if (logicalField == 'nameId') {
            e.WhoId = value == null ? null : (Id) String.valueOf(value);
        } else if (logicalField == 'assignedToId') {
            e.OwnerId = value == null ? null : (Id) String.valueOf(value);
        }
    }

    private static Date parseIsoDate(String isoDate) {
        return (Date) JSON.deserialize('"' + isoDate + '"', Date.class);
    }

    private static Datetime parseIsoDateTime(String isoDateTime) {
        return (Datetime) JSON.deserialize('"' + isoDateTime + '"', Datetime.class);
    }

    private static void collectDmlErrors(List<Database.SaveResult> saveResults, List<String> errors) {
        for (Database.SaveResult sr : saveResults) {
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    errors.add(err.getMessage());
                }
            }
        }
    }

    // See getActivities for why these take JSON strings rather than List<Id>/List<String>
    // parameters directly.
    @AuraEnabled
    public static SaveResult deleteActivities(String recordIdsJson, String activityTypesJson) {
        SaveResult result = new SaveResult();
        try {
            List<Id> recordIds = (List<Id>) JSON.deserialize(recordIdsJson, List<Id>.class);
            List<String> activityTypes = (List<String>) JSON.deserialize(activityTypesJson, List<String>.class);
            List<Task> tasksToDelete = new List<Task>();
            List<Event> eventsToDelete = new List<Event>();
            for (Integer i = 0; i < recordIds.size(); i++) {
                if (activityTypes[i] == 'Task') {
                    tasksToDelete.add(new Task(Id = recordIds[i]));
                } else if (activityTypes[i] == 'Event') {
                    eventsToDelete.add(new Event(Id = recordIds[i]));
                }
            }
            if (!tasksToDelete.isEmpty() && Schema.SObjectType.Task.isDeletable()) {
                collectDeleteErrors(Database.delete(tasksToDelete, false), result.errors);
            }
            if (!eventsToDelete.isEmpty() && Schema.SObjectType.Event.isDeletable()) {
                collectDeleteErrors(Database.delete(eventsToDelete, false), result.errors);
            }
            result.success = result.errors.isEmpty();
            return result;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to delete activities: ' + ex.getMessage());
        }
    }

    private static void collectDeleteErrors(List<Database.DeleteResult> deleteResults, List<String> errors) {
        for (Database.DeleteResult dr : deleteResults) {
            if (!dr.isSuccess()) {
                for (Database.Error err : dr.getErrors()) {
                    errors.add(err.getMessage());
                }
            }
        }
    }

}
