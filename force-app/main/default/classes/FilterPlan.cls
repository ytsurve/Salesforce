/**
 * Result of translating the UI's structured filter conditions + logic string into a
 * WHERE clause for each of Task and Event, along with the bind variables both clauses
 * reference. taskClause/eventClause equal ALWAYS_FALSE when the filter logic can never
 * match that object at all (e.g. "Activity Type = Event" folds Task's clause to false),
 * letting the caller skip querying that object entirely.
 */
public class FilterPlan {
    public static final String ALWAYS_FALSE = '__ALWAYS_FALSE__';

    public String taskClause;
    public String eventClause;
    public Map<String, Object> binds = new Map<String, Object>();
}
