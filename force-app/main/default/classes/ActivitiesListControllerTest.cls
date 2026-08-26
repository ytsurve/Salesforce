@IsTest
private class ActivitiesListControllerTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'FilterTestAccount', Website = 'https://www.filtertestaccount.example.com');
        insert acc;

        Contact con = new Contact(LastName = 'FilterTestContact');
        insert con;

        // Owned by a User created BY this test, not the running context user. Apex tests can't
        // see relationship-traversed data on pre-existing "setup" records (Users, RecordTypes,
        // etc.) without @IsTest(SeeAllData=true) - so Owner.Name would silently resolve to null
        // for records owned by the ambient running user, which in turn makes any WHERE clause
        // that ORs Owner.Name against other conditions match nothing at all (a Salesforce SOQL
        // testing gotcha, not a bug in the search feature - confirmed this doesn't happen outside
        // test context). Owning test records by a test-created user sidesteps it entirely.
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User testOwner = new User(
            FirstName = 'Activities',
            LastName = 'TestOwner',
            Email = 'activities.test.owner@example.com',
            Username = 'activities.test.owner.' + UserInfo.getOrganizationId() + '@example.com',
            Alias = 'actodt',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardProfile.Id
        );
        insert testOwner;

        List<Task> tasks = new List<Task>();
        for (Integer i = 0; i < 5; i++) {
            tasks.add(new Task(
                Subject = 'Task Subject ' + i,
                ActivityDate = Date.today().addDays(i),
                Status = 'Not Started',
                Priority = 'Normal',
                WhoId = con.Id,
                OwnerId = testOwner.Id
            ));
        }
        insert tasks;

        List<Event> events = new List<Event>();
        for (Integer i = 0; i < 3; i++) {
            events.add(new Event(
                Subject = 'Event Subject ' + i,
                StartDateTime = Datetime.now().addDays(i),
                EndDateTime = Datetime.now().addDays(i).addHours(1),
                WhoId = con.Id,
                OwnerId = testOwner.Id
            ));
        }
        insert events;
    }

    @IsTest
    static void testGetActivitiesReturnsBothTypesMerged() {
        ActivitiesListController.QueryRequest req = new ActivitiesListController.QueryRequest();
        req.pageOffset = 0;
        req.pageSize = 50;

        Test.startTest();
        ActivitiesListController.ActivitiesResult result = ActivitiesListController.getActivities(JSON.serialize(req));
        Test.stopTest();

        Set<String> types = new Set<String>();
        for (ActivitiesListController.ActivityRow row : result.rows) {
            types.add(row.activityType);
        }
        System.assertEquals(8, result.rows.size(), 'Expected all 5 tasks + 3 events');
        System.assert(types.contains('Task'));
        System.assert(types.contains('Event'));
        System.assertEquals(false, result.hasMore);
        System.assertEquals(true, result.subjectColumnEditable);
        System.assertEquals(true, result.dateColumnEditable);
        System.assertEquals(true, result.relatedToColumnEditable);
        System.assertEquals(true, result.nameColumnEditable);
        System.assertEquals(true, result.assignedToColumnEditable);
        for (ActivitiesListController.ActivityRow row : result.rows) {
            System.assertEquals(true, row.subjectEditable);
            System.assertEquals(true, row.dateEditable);
            System.assertEquals(true, row.relatedToEditable);
            System.assertEquals(true, row.nameEditable);
            System.assertEquals(true, row.assignedToEditable);
        }
    }

    @IsTest
    static void testPaginationHasMoreFlag() {
        ActivitiesListController.QueryRequest req = new ActivitiesListController.QueryRequest();
        req.pageOffset = 0;
        req.pageSize = 3;
        req.sortField = 'subject';
        req.sortDirection = 'asc';

        Test.startTest();
        ActivitiesListController.ActivitiesResult firstPage = ActivitiesListController.getActivities(JSON.serialize(req));
        Test.stopTest();

        System.assertEquals(3, firstPage.rows.size());
        System.assertEquals(true, firstPage.hasMore);
    }

    private static ActivitiesListController.ActivitiesResult search(String term) {
        ActivitiesListController.QueryRequest req = new ActivitiesListController.QueryRequest();
        req.searchTerm = term;
        req.pageOffset = 0;
        req.pageSize = 50;
        return ActivitiesListController.getActivities(JSON.serialize(req));
    }

    @IsTest
    static void testSearchMatchesOnAssignedToAcrossBothObjects() {
        // Every setup Task and Event is owned by the test-created "Activities TestOwner" user, so
        // searching a fragment of that owner's name returns all of them.
        Test.startTest();
        ActivitiesListController.ActivitiesResult result = search('TestOwner');
        Test.stopTest();

        Set<String> types = new Set<String>();
        for (ActivitiesListController.ActivityRow row : result.rows) {
            types.add(row.activityType);
        }
        System.assertEquals(8, result.rows.size(), 'All 5 tasks + 3 events are owned by the searched user');
        System.assert(types.contains('Task'));
        System.assert(types.contains('Event'));
    }

    @IsTest
    static void testSearchMatchesOnSubject() {
        Test.startTest();
        ActivitiesListController.ActivitiesResult result = search('Task Subject 2');
        Test.stopTest();

        System.assertEquals(1, result.rows.size());
        System.assertEquals('Task Subject 2', result.rows[0].subject);
    }

    @IsTest
    static void testSearchMatchesOnNameContact() {
        // Every setup activity points at the same Contact via WhoId.
        Test.startTest();
        ActivitiesListController.ActivitiesResult result = search('FilterTestContact');
        Test.stopTest();

        System.assertEquals(8, result.rows.size(), 'All 8 activities share the searched Contact');
    }

    @IsTest
    static void testSearchMatchesOnRelatedTo() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'FilterTestAccount' LIMIT 1];
        Task related = [SELECT Id FROM Task WHERE Subject = 'Task Subject 3' LIMIT 1];
        update new Task(Id = related.Id, WhatId = acc.Id);

        Test.startTest();
        ActivitiesListController.ActivitiesResult result = search('FilterTestAccount');
        Test.stopTest();

        System.assertEquals(1, result.rows.size(), 'Only the task related to that account matches');
        System.assertEquals(related.Id, result.rows[0].recordId);
    }

    @IsTest
    static void testSearchMatchingNothingReturnsNoRows() {
        Test.startTest();
        ActivitiesListController.ActivitiesResult result = search('NoSuchValueExistsAnywhereHere');
        Test.stopTest();

        System.assertEquals(0, result.rows.size());
    }

    @IsTest
    static void testSearchTermWithSoslReservedCharactersIsNotAnError() {
        // Regression guard: the previous SOSL-based search rejected ordinary punctuation outright
        // ("Invalid string literal ... Illegal character sequence '\\[' in string literal"). The
        // term now only ever reaches the database as a bind variable, so these are just characters.
        Task punctuated = [SELECT Id FROM Task WHERE Subject = 'Task Subject 4' LIMIT 1];
        update new Task(Id = punctuated.Id, Subject = '[Gong] Samba x WPP | Lunch');

        Test.startTest();
        ActivitiesListController.ActivitiesResult result = search('[Gong] Samba x WPP | Lunch');
        Test.stopTest();

        System.assertEquals(1, result.rows.size(), 'Reserved characters are matched literally, not rejected');
        System.assertEquals('[Gong] Samba x WPP | Lunch', result.rows[0].subject);
    }

    private static ActivitiesListController.ActivitiesResult view(String viewName) {
        ActivitiesListController.QueryRequest req = new ActivitiesListController.QueryRequest();
        req.view = viewName;
        req.pageOffset = 0;
        req.pageSize = 50;
        return ActivitiesListController.getActivities(JSON.serialize(req));
    }

    @IsTest
    static void testBackstoryViewExcludesRecordsNotCreatedByThatUser() {
        // None of the @TestSetup records were created by the Backstory Integration User (its Id
        // is a fixed Custom Label value, not the running test context user) - so the Backstory
        // view should legitimately come back empty, the same way it does in an org/sandbox where
        // that user has no activity yet.
        Test.startTest();
        ActivitiesListController.ActivitiesResult result = view('backstory');
        Test.stopTest();

        System.assertEquals(0, result.rows.size(), 'No setup records were created by the Backstory Integration User');
    }

    @IsTest
    static void testMyViewReturnsRecordsCreatedByRunningUser() {
        // @TestSetup records are created by the test-running user, and owned by a different
        // (test-created) user - so "My Activities" (created by me) must return all of them even
        // though none are assigned to me.
        Test.startTest();
        ActivitiesListController.ActivitiesResult result = view('my');
        Test.stopTest();

        System.assertEquals(8, result.rows.size(), 'All 8 setup activities were created by the running user');
        for (ActivitiesListController.ActivityRow row : result.rows) {
            System.assertNotEquals(UserInfo.getUserId(), row.assignedToId, 'Setup records are owned by another user');
        }
    }

    @IsTest
    static void testMyBackstoryViewRequiresBothCreatedByAndOwnership() {
        // Created by the running user, not the integration, so this view excludes them regardless
        // of ownership - it is the AND of "created by Backstory" and "assigned to me".
        Test.startTest();
        ActivitiesListController.ActivitiesResult result = view('myBackstory');
        Test.stopTest();

        System.assertEquals(0, result.rows.size(), 'Nothing was created by the integration user');
    }

    @IsTest
    static void testUnrecognisedViewFallsBackToEverything() {
        Test.startTest();
        ActivitiesListController.ActivitiesResult result = view('notAView');
        Test.stopTest();

        System.assertEquals(8, result.rows.size(), 'An unknown view must not silently hide rows');
    }

    @IsTest
    static void testNullRequestDefaultsGracefully() {
        Test.startTest();
        ActivitiesListController.ActivitiesResult result = ActivitiesListController.getActivities(null);
        Test.stopTest();

        System.assertEquals(8, result.rows.size());
    }

    @IsTest
    static void testDefaultSortIsActivityDateDescending() {
        ActivitiesListController.QueryRequest req = new ActivitiesListController.QueryRequest();
        req.pageOffset = 0;
        req.pageSize = 50;

        Test.startTest();
        ActivitiesListController.ActivitiesResult result = ActivitiesListController.getActivities(JSON.serialize(req));
        Test.stopTest();

        Datetime previous;
        for (ActivitiesListController.ActivityRow row : result.rows) {
            Datetime current;
            if (row.dateOnly) {
                // newInstanceGmt, not newInstance: a Task's date-only value is placed at GMT
                // midnight by the merge comparator, so reconstructing it at LOCAL midnight here
                // shifts it by the running user's offset and makes this assertion pass or fail
                // depending on the time of day it runs.
                current = Datetime.newInstanceGmt(Date.valueOf(row.activityDateEditValue), Time.newInstance(0, 0, 0, 0));
            } else {
                String core = row.activityDateEditValue.substring(0, 19).replace('T', ' ');
                current = Datetime.valueOfGmt(core);
            }
            if (previous != null) {
                System.assert(current <= previous, 'Rows should be ordered most-recent-first by default');
            }
            previous = current;
        }
    }

    @IsTest
    static void testGetLookupDisplayNameResolvesFromIdAlone() {
        // The object type is derived from the Id itself (WhatId is polymorphic), and the display
        // field from each object's own name field - so Account/Contact resolve via Name while
        // Case resolves via CaseNumber, with no per-object configuration.
        Account acc = [SELECT Id FROM Account WHERE Name = 'FilterTestAccount' LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'FilterTestContact' LIMIT 1];
        Case supportCase = new Case(Subject = 'Lookup Display Name Case');
        insert supportCase;
        String expectedCaseNumber = [SELECT CaseNumber FROM Case WHERE Id = :supportCase.Id].CaseNumber;

        Test.startTest();
        String accountName = ActivitiesListController.getLookupDisplayName(acc.Id);
        String contactName = ActivitiesListController.getLookupDisplayName(con.Id);
        String caseName = ActivitiesListController.getLookupDisplayName(supportCase.Id);
        String nullId = ActivitiesListController.getLookupDisplayName(null);
        Test.stopTest();

        System.assertEquals('FilterTestAccount', accountName);
        System.assertEquals('FilterTestContact', contactName);
        System.assertEquals(expectedCaseNumber, caseName, 'Case has no Name field; its CaseNumber is the name field');
        System.assertEquals(null, nullId);
    }

    @IsTest
    static void testSaveActivitiesUpdatesTaskSubjectAndDate() {
        Task t = [SELECT Id FROM Task WHERE Subject = 'Task Subject 0' LIMIT 1];

        ActivitiesListController.ActivityDraft draft = new ActivitiesListController.ActivityDraft();
        draft.recordId = t.Id;
        draft.activityType = 'Task';
        draft.changedFields = new Map<String, Object>{
            'subject' => 'Updated Task Subject',
            'activityDateEditValue' => String.valueOf(Date.today().addDays(10))
        };

        Test.startTest();
        ActivitiesListController.SaveResult result = ActivitiesListController.saveActivities(
            JSON.serialize(new List<ActivitiesListController.ActivityDraft>{ draft })
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        Task updated = [SELECT Subject, ActivityDate FROM Task WHERE Id = :t.Id];
        System.assertEquals('Updated Task Subject', updated.Subject);
        System.assertEquals(Date.today().addDays(10), updated.ActivityDate);
    }

    @IsTest
    static void testSaveActivitiesUpdatesLookupFields() {
        Task t = [SELECT Id FROM Task WHERE Subject = 'Task Subject 1' LIMIT 1];
        Account acc = [SELECT Id FROM Account WHERE Name = 'FilterTestAccount' LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'FilterTestContact' LIMIT 1];
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        ActivitiesListController.ActivityDraft draft = new ActivitiesListController.ActivityDraft();
        draft.recordId = t.Id;
        draft.activityType = 'Task';
        draft.changedFields = new Map<String, Object>{
            'relatedToId' => acc.Id,
            'nameId' => con.Id,
            'assignedToId' => currentUser.Id
        };

        Test.startTest();
        ActivitiesListController.SaveResult result = ActivitiesListController.saveActivities(
            JSON.serialize(new List<ActivitiesListController.ActivityDraft>{ draft })
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        Task updated = [SELECT WhatId, WhoId, OwnerId FROM Task WHERE Id = :t.Id];
        System.assertEquals(acc.Id, updated.WhatId);
        System.assertEquals(con.Id, updated.WhoId);
        System.assertEquals(currentUser.Id, updated.OwnerId);
    }

    @IsTest
    static void testSaveActivitiesShiftsEventEndDateTimeToPreserveDuration() {
        Event e = [SELECT Id, StartDateTime, EndDateTime FROM Event WHERE Subject = 'Event Subject 0' LIMIT 1];
        Datetime newStart = e.StartDateTime.addDays(5);

        ActivitiesListController.ActivityDraft draft = new ActivitiesListController.ActivityDraft();
        draft.recordId = e.Id;
        draft.activityType = 'Event';
        draft.changedFields = new Map<String, Object>{
            'activityDateEditValue' => e.StartDateTime.addDays(5).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
        };

        Test.startTest();
        ActivitiesListController.SaveResult result = ActivitiesListController.saveActivities(
            JSON.serialize(new List<ActivitiesListController.ActivityDraft>{ draft })
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        Event updated = [SELECT StartDateTime, EndDateTime FROM Event WHERE Id = :e.Id];
        Long originalDurationMs = e.EndDateTime.getTime() - e.StartDateTime.getTime();
        Long newDurationMs = updated.EndDateTime.getTime() - updated.StartDateTime.getTime();
        System.assertEquals(originalDurationMs, newDurationMs, 'Duration should be preserved after shifting start time');
    }

    @IsTest
    static void testSaveActivitiesBulk() {
        List<Task> tasks = [SELECT Id FROM Task];
        List<ActivitiesListController.ActivityDraft> drafts = new List<ActivitiesListController.ActivityDraft>();
        for (Task t : tasks) {
            ActivitiesListController.ActivityDraft draft = new ActivitiesListController.ActivityDraft();
            draft.recordId = t.Id;
            draft.activityType = 'Task';
            draft.changedFields = new Map<String, Object>{ 'subject' => 'Bulk Updated' };
            drafts.add(draft);
        }

        Test.startTest();
        ActivitiesListController.SaveResult result = ActivitiesListController.saveActivities(JSON.serialize(drafts));
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(5, [SELECT COUNT() FROM Task WHERE Subject = 'Bulk Updated']);
    }

    @IsTest
    static void testSaveActivitiesIgnoresDraftsWithNoChangedFields() {
        Task t = [SELECT Id, Subject FROM Task LIMIT 1];
        ActivitiesListController.ActivityDraft draft = new ActivitiesListController.ActivityDraft();
        draft.recordId = t.Id;
        draft.activityType = 'Task';
        draft.changedFields = null;

        Test.startTest();
        ActivitiesListController.SaveResult result = ActivitiesListController.saveActivities(
            JSON.serialize(new List<ActivitiesListController.ActivityDraft>{ draft })
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
    }

    @IsTest
    static void testDeleteActivitiesRemovesTaskAndEvent() {
        Task t = [SELECT Id FROM Task LIMIT 1];
        Event e = [SELECT Id FROM Event LIMIT 1];

        Test.startTest();
        ActivitiesListController.SaveResult result = ActivitiesListController.deleteActivities(
            JSON.serialize(new List<Id>{ t.Id, e.Id }),
            JSON.serialize(new List<String>{ 'Task', 'Event' })
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(4, [SELECT COUNT() FROM Task]);
        System.assertEquals(2, [SELECT COUNT() FROM Event]);
    }

    @IsTest
    static void testDeleteActivitiesEmptyListIsNoop() {
        Test.startTest();
        ActivitiesListController.SaveResult result = ActivitiesListController.deleteActivities(
            JSON.serialize(new List<Id>()), JSON.serialize(new List<String>())
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
    }
}
