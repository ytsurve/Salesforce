/**
 * Maps the logical sort keys used by the Activities List UI onto the real SOQL column for Task
 * vs Event, since the two objects model the same concept with different field names (ActivityDate
 * vs StartDateTime).
 */
public with sharing class ActivityFieldMap {

    public static String taskSortColumn(String logicalField) {
        if (logicalField == 'activityDate') return 'ActivityDate';
        if (logicalField == 'assignedToName') return 'Owner.Name';
        if (logicalField == 'relatedToName') return 'What.Name';
        if (logicalField == 'name') return 'Who.Name';
        if (logicalField == 'activityType') return 'CreatedDate';
        return 'Subject';
    }

    public static String eventSortColumn(String logicalField) {
        if (logicalField == 'activityDate') return 'StartDateTime';
        if (logicalField == 'assignedToName') return 'Owner.Name';
        if (logicalField == 'relatedToName') return 'What.Name';
        if (logicalField == 'name') return 'Who.Name';
        if (logicalField == 'activityType') return 'CreatedDate';
        return 'Subject';
    }
}
