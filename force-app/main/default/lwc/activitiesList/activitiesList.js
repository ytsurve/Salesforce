import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getActivities from '@salesforce/apex/ActivitiesListController.getActivities';
import saveActivities from '@salesforce/apex/ActivitiesListController.saveActivities';
import deleteActivities from '@salesforce/apex/ActivitiesListController.deleteActivities';
import getLookupDisplayName from '@salesforce/apex/ActivitiesListController.getLookupDisplayName';

import titleLabel from '@salesforce/label/c.Activities_List_Title';
import newTaskLabel from '@salesforce/label/c.Activities_New_Task';
import newEventLabel from '@salesforce/label/c.Activities_New_Event';
import searchPlaceholderLabel from '@salesforce/label/c.Activities_Search_Placeholder';
import searchButtonLabel from '@salesforce/label/c.Activities_Search_Button';
import viewAllLabel from '@salesforce/label/c.Activities_View_All';
import viewBackstoryLabel from '@salesforce/label/c.Activities_View_Backstory';
import viewMyLabel from '@salesforce/label/c.Activities_View_My';
import viewMyBackstoryLabel from '@salesforce/label/c.Activities_View_My_Backstory';
import viewPickerLabel from '@salesforce/label/c.Activities_View_Picker_Label';
import emptyStateLabel from '@salesforce/label/c.Activities_Empty_State';
import saveSuccessLabel from '@salesforce/label/c.Activities_Save_Success';
import saveErrorLabel from '@salesforce/label/c.Activities_Save_Error';
import deleteConfirmTitleLabel from '@salesforce/label/c.Activities_Delete_Confirm_Title';
import deleteConfirmMessageLabel from '@salesforce/label/c.Activities_Delete_Confirm_Message';
import deleteSuccessLabel from '@salesforce/label/c.Activities_Delete_Success';
import loadErrorLabel from '@salesforce/label/c.Activities_Load_Error';

const PAGE_SIZE = 50;
const SEARCH_DEBOUNCE_MS = 300;
// A single character matches almost every owner in the org, so it isn't a useful filter - treat
// it as "no search yet" rather than round-tripping to the server for nothing.
const MIN_SEARCH_LENGTH = 2;

// Activity/Related To/Name/Assigned To cells link to their record. A bare record-Id path is used
// rather than the /lightning/r/{objectApiName}/{id}/view form because Related To is polymorphic
// (and a lookup can be re-pointed at a different object mid-edit); Salesforce resolves the Id to
// the right record page on its own, so no object name is needed here.
function recordUrl(recordId) {
    return recordId ? `/${recordId}` : null;
}

// Maps a column's datatable fieldName to the logical sort key the server understands, and back.
// Every custom-typed column uses a synthetic/reference fieldName (recordId, activityDateEditValue,
// relatedToId, nameId, assignedToId) rather than the display text, so each needs an explicit
// mapping to the logical (display-oriented) sort key the server understands, and back.
const FIELD_NAME_TO_SORT_KEY = {
    recordId: 'activityType',
    subject: 'subject',
    relatedToId: 'relatedToName',
    nameId: 'name',
    activityDateEditValue: 'activityDate',
    assignedToId: 'assignedToName'
};
const SORT_KEY_TO_FIELD_NAME = {
    activityType: 'recordId',
    subject: 'subject',
    relatedToName: 'relatedToId',
    name: 'nameId',
    activityDate: 'activityDateEditValue',
    assignedToName: 'assignedToId'
};

// WhoId (Name) is scoped to Contact only - this org doesn't use Lead on activities. WhatId
// (Related To) is open-ended (any activity-enabled object); this is a curated common subset -
// extend it if this org relates activities to other objects. Assigned To is scoped to User only
// (queue-owned activities still exist but are a rarer case better handled via the standard Edit
// panel).
const RELATED_TO_OBJECT_OPTIONS = [
    { label: 'Account', value: 'Account' },
    { label: 'Opportunity', value: 'Opportunity' },
    { label: 'Case', value: 'Case' },
    { label: 'Contract', value: 'Contract' },
    { label: 'Campaign', value: 'Campaign' }
];
const NAME_OBJECT_OPTIONS = [{ label: 'Contact', value: 'Contact' }];
const ASSIGNED_TO_OBJECT_OPTIONS = [{ label: 'User', value: 'User' }];

// Maps each inline-editable draft field to the per-row ActivityRow flag that gates it.
const EDITABLE_FLAG_BY_FIELD = {
    subject: 'subjectEditable',
    activityDateEditValue: 'dateEditable',
    relatedToId: 'relatedToEditable',
    nameId: 'nameEditable',
    assignedToId: 'assignedToEditable'
};

// The preset views, in the order they appear in the picker. Values must match the view names
// ActivitiesListController.applyViewFilter recognises. "My Activities" means created by the
// running user; "My Backstory Activities" means created by the integration and assigned to them.
const VIEW_OPTIONS = [
    { label: viewAllLabel, value: 'all' },
    { label: viewMyLabel, value: 'my' },
    { label: viewBackstoryLabel, value: 'backstory' },
    { label: viewMyBackstoryLabel, value: 'myBackstory' }
];

// Lookup columns edit an Id field but DISPLAY a name field (and link to a record), so the
// datatable cannot refresh the visible text by itself when a draft is committed - each edited Id
// maps here to the row properties the column actually renders, which handleCellChange repaints
// from the resolved record.
const LOOKUP_PREVIEW_BY_ID_FIELD = {
    relatedToId: { displayField: 'relatedToName', urlField: 'relatedToUrl' },
    nameId: { displayField: 'name', urlField: 'nameUrl' },
    assignedToId: { displayField: 'assignedToName', urlField: 'assignedToUrl' }
};

// Formats a drafted date/datetime for the same kind of immediate preview (the date column edits
// activityDateEditValue but displays activityDateDisplay). This is a client-side stand-in shown
// only until Save reloads the server-formatted value, so it need not match that formatting byte
// for byte.
function formatDraftDateDisplay(rawValue, dateOnly) {
    if (!rawValue) {
        return '';
    }
    const parsed = dateOnly ? new Date(`${rawValue}T00:00:00`) : new Date(rawValue);
    if (Number.isNaN(parsed.getTime())) {
        return '';
    }
    return dateOnly ? parsed.toLocaleDateString() : parsed.toLocaleString();
}

export default class ActivitiesList extends NavigationMixin(LightningElement) {
    labels = {
        title: titleLabel,
        newTask: newTaskLabel,
        newEvent: newEventLabel,
        searchPlaceholder: searchPlaceholderLabel,
        searchButton: searchButtonLabel,
        viewPicker: viewPickerLabel,
        emptyState: emptyStateLabel,
        saveSuccess: saveSuccessLabel,
        saveError: saveErrorLabel,
        deleteConfirmTitle: deleteConfirmTitleLabel,
        deleteConfirmMessage: deleteConfirmMessageLabel,
        deleteSuccess: deleteSuccessLabel,
        loadError: loadErrorLabel
    };

    rows = [];
    hasMore = false;
    isLoading = true;
    isSaving = false;
    draftValues = [];

    // Server-truth copy of the current page, kept so Cancel can undo the local display-text
    // previews handleCellChange paints onto this.rows without re-querying.
    pristineRows = [];

    searchTerm = '';
    // Opens on the user's own activities rather than the whole org's. Note this is a UI default
    // only: a request that omits the view entirely still means "everything" server-side, so the
    // Apex stays predictable for any other caller rather than applying an implicit filter.
    activeView = 'my';
    sortField = 'activityDate';
    // Most-recent-first by default - matches this being an activity feed, not an alphabetical
    // record list.
    sortDirection = 'desc';
    pageNumber = 1;

    subjectColumnEditable = false;
    dateColumnEditable = false;
    relatedToColumnEditable = false;
    nameColumnEditable = false;
    assignedToColumnEditable = false;

    searchDebounceHandle;
    latestRequestToken;

    connectedCallback() {
        this.loadActivities(true);
    }

    get columns() {
        return [
            {
                label: 'Activity',
                fieldName: 'recordId',
                type: 'activityIndicator',
                sortable: true,
                hideDefaultActions: true,
                typeAttributes: {
                    iconName: { fieldName: 'activityIconName' },
                    label: { fieldName: 'activityType' },
                    recordId: { fieldName: 'recordId' },
                    objectApiName: { fieldName: 'activityType' }
                }
            },
            {
                label: 'Subject',
                fieldName: 'subject',
                type: 'activityLink',
                editable: this.subjectColumnEditable,
                sortable: true,
                typeAttributes: {
                    recordId: { fieldName: 'recordId' },
                    objectApiName: { fieldName: 'activityType' },
                    displayName: { fieldName: 'subject' },
                    url: { fieldName: 'subjectUrl' }
                }
            },
            {
                label: 'Related To',
                fieldName: 'relatedToId',
                type: 'activityLookupLink',
                editable: this.relatedToColumnEditable,
                sortable: true,
                typeAttributes: {
                    recordId: { fieldName: 'relatedToId' },
                    objectApiName: { fieldName: 'relatedToObjectApiName' },
                    displayName: { fieldName: 'relatedToName' },
                    url: { fieldName: 'relatedToUrl' },
                    objectOptions: RELATED_TO_OBJECT_OPTIONS
                }
            },
            {
                label: 'Name',
                fieldName: 'nameId',
                type: 'activityLookupLink',
                editable: this.nameColumnEditable,
                sortable: true,
                typeAttributes: {
                    recordId: { fieldName: 'nameId' },
                    objectApiName: { fieldName: 'nameObjectApiName' },
                    displayName: { fieldName: 'name' },
                    url: { fieldName: 'nameUrl' },
                    objectOptions: NAME_OBJECT_OPTIONS
                }
            },
            {
                label: 'Activity Date/Start Date',
                fieldName: 'activityDateEditValue',
                type: 'activityDate',
                editable: this.dateColumnEditable,
                sortable: true,
                typeAttributes: {
                    displayValue: { fieldName: 'activityDateDisplay' },
                    dateOnly: { fieldName: 'dateOnly' }
                }
            },
            {
                label: 'Assigned To',
                fieldName: 'assignedToId',
                type: 'activityLookupLink',
                editable: this.assignedToColumnEditable,
                sortable: true,
                // "required" is a reserved column-level property the edit template contract binds
                // directly (not one of typeAttributes) - Owner can never be blank on Task/Event.
                required: true,
                typeAttributes: {
                    recordId: { fieldName: 'assignedToId' },
                    objectApiName: { fieldName: 'assignedToObjectApiName' },
                    displayName: { fieldName: 'assignedToName' },
                    url: { fieldName: 'assignedToUrl' },
                    objectOptions: ASSIGNED_TO_OBJECT_OPTIONS
                }
            },
            {
                type: 'action',
                typeAttributes: { rowActions: this.getRowActions.bind(this) }
            }
        ];
    }

    get sortedByFieldName() {
        return SORT_KEY_TO_FIELD_NAME[this.sortField] || 'subject';
    }

    get showEmptyState() {
        return !this.isLoading && this.rows.length === 0;
    }

    get viewOptions() {
        return VIEW_OPTIONS;
    }

    get isFirstPage() {
        return this.pageNumber <= 1;
    }

    get isPreviousDisabled() {
        return this.isLoading || this.isFirstPage;
    }

    get isNextDisabled() {
        return this.isLoading || !this.hasMore;
    }

    // lightning-datatable numbers its rows from 1 on every render, so without this the second page
    // would restart at 1 instead of continuing at 51.
    get rowNumberOffset() {
        return (this.pageNumber - 1) * PAGE_SIZE;
    }

    get pageRangeLabel() {
        if (this.rows.length === 0) {
            return '';
        }
        const start = (this.pageNumber - 1) * PAGE_SIZE + 1;
        const end = start + this.rows.length - 1;
        return `${start}-${end}`;
    }

    async loadActivities(reset) {
        if (reset) {
            this.pageNumber = 1;
        }
        this.isLoading = true;
        const request = {
            searchTerm: this.searchTerm,
            view: this.activeView,
            sortField: this.sortField,
            sortDirection: this.sortDirection,
            pageOffset: (this.pageNumber - 1) * PAGE_SIZE,
            pageSize: PAGE_SIZE
        };
        // Search/filter/sort/page can each fire their own call in quick succession, and network
        // timing gives no guarantee an earlier call's response won't resolve after a later one's -
        // without this token, that stale response would silently overwrite the correct, newer
        // result. Only the most recently DISPATCHED call is allowed to write to this.rows.
        const requestToken = Symbol('loadActivities');
        this.latestRequestToken = requestToken;
        try {
            // Sent as a JSON string, not the plain object - passing a nested object straight
            // through as an @AuraEnabled parameter was confirmed unreliable on this Aura-hosted
            // page (every field arrived null server-side despite being set correctly here).
            const result = await getActivities({ requestJson: JSON.stringify(request) });
            if (this.latestRequestToken !== requestToken) {
                return;
            }
            const rowsWithLinks = result.rows.map((row) => ({
                ...row,
                subjectUrl: recordUrl(row.recordId),
                relatedToUrl: recordUrl(row.relatedToId),
                nameUrl: recordUrl(row.nameId),
                assignedToUrl: recordUrl(row.assignedToId)
            }));
            this.rows = rowsWithLinks;
            this.pristineRows = rowsWithLinks.map((row) => ({ ...row }));
            this.hasMore = result.hasMore;
            this.subjectColumnEditable = result.subjectColumnEditable;
            this.dateColumnEditable = result.dateColumnEditable;
            this.relatedToColumnEditable = result.relatedToColumnEditable;
            this.nameColumnEditable = result.nameColumnEditable;
            this.assignedToColumnEditable = result.assignedToColumnEditable;
        } catch (error) {
            if (this.latestRequestToken !== requestToken) {
                return;
            }
            this.showToast('Error', this.reduceError(error) || this.labels.loadError, 'error');
        } finally {
            if (this.latestRequestToken === requestToken) {
                this.isLoading = false;
            }
        }
    }

    handleRefresh() {
        this.loadActivities(false);
    }

    handlePreviousPage() {
        if (this.isPreviousDisabled) {
            return;
        }
        this.pageNumber -= 1;
        this.loadActivities(false);
    }

    handleNextPage() {
        if (this.isNextDisabled) {
            return;
        }
        this.pageNumber += 1;
        this.loadActivities(false);
    }

    handleSearchChange(event) {
        // event.detail.value, not event.target.value - the latter silently stayed empty in this
        // Aura-hosted LWC context, which is what made search look like it was doing nothing at
        // all (it was always sending an empty searchTerm). Every other Lightning base component
        // handler in this codebase already used event.detail.value; this was the one place that
        // didn't, and it happened to be the bug.
        const rawValue = event.detail.value || '';
        this.searchTerm = rawValue;
        window.clearTimeout(this.searchDebounceHandle);
        const trimmedLength = rawValue.trim().length;
        if (trimmedLength > 0 && trimmedLength < MIN_SEARCH_LENGTH) {
            return;
        }
        this.searchDebounceHandle = window.setTimeout(() => {
            this.loadActivities(true);
        }, SEARCH_DEBOUNCE_MS);
    }

    handleSort(event) {
        this.sortField = FIELD_NAME_TO_SORT_KEY[event.detail.fieldName] || 'subject';
        this.sortDirection = event.detail.sortDirection;
        this.loadActivities(true);
    }

    handleSearchNow() {
        window.clearTimeout(this.searchDebounceHandle);
        this.loadActivities(true);
    }

    handleViewChange(event) {
        const selected = event.detail.value;
        if (!selected || selected === this.activeView) {
            return;
        }
        this.activeView = selected;
        // Switching view invalidates any in-flight edits: the rows they belong to may not be in
        // the new view at all.
        this.draftValues = [];
        this.loadActivities(true);
    }

    /**
     * Fires each time the datatable commits an inline-edit draft (public `cellchange` event).
     *
     * Two things happen here that standard Salesforce inline edit does for free:
     *
     * 1. draftValues is kept in sync, so the edited cells keep their pending-change highlight and
     *    the Save/Cancel bar stays up until the user resolves them.
     * 2. The visible text is repainted. Subject needs nothing - it edits and displays the same
     *    field. But the lookup columns edit an Id while displaying a name, and the date column
     *    edits an ISO value while displaying formatted text, so for those the datatable has no way
     *    to derive the new display text itself and the cell would keep showing the old value until
     *    a save round trip. Resolving it here is what makes the picked/typed value appear at once.
     */
    async handleCellChange(event) {
        const changedDrafts = event.detail.draftValues || [];
        if (changedDrafts.length === 0) {
            return;
        }

        const mergedByRecordId = new Map(this.draftValues.map((draft) => [draft.recordId, { ...draft }]));
        for (const draft of changedDrafts) {
            mergedByRecordId.set(draft.recordId, { ...(mergedByRecordId.get(draft.recordId) || {}), ...draft });
        }
        this.draftValues = [...mergedByRecordId.values()];

        for (const draft of changedDrafts) {
            const patch = await this.buildDisplayPatch(draft);
            if (patch) {
                this.rows = this.rows.map((row) => (row.recordId === draft.recordId ? { ...row, ...patch } : row));
            }
        }
    }

    async buildDisplayPatch(draft) {
        const row = this.rows.find((candidate) => candidate.recordId === draft.recordId);
        if (!row) {
            return null;
        }
        const patch = {};

        if (Object.prototype.hasOwnProperty.call(draft, 'activityDateEditValue')) {
            patch.activityDateDisplay = formatDraftDateDisplay(draft.activityDateEditValue, row.dateOnly);
        }

        for (const [idField, { displayField, urlField }] of Object.entries(LOOKUP_PREVIEW_BY_ID_FIELD)) {
            if (!Object.prototype.hasOwnProperty.call(draft, idField)) {
                continue;
            }
            const newRecordId = draft[idField];
            if (!newRecordId) {
                // Lookup was cleared - blank the display text and drop the link to match.
                patch[displayField] = '';
                patch[urlField] = null;
                continue;
            }
            patch[urlField] = recordUrl(newRecordId);
            const displayName = await this.resolveLookupDisplayName(newRecordId);
            // A null result means the record isn't readable by this user; leave the existing text
            // rather than blanking the cell on what is only a cosmetic preview.
            if (displayName) {
                patch[displayField] = displayName;
            }
        }

        return Object.keys(patch).length > 0 ? patch : null;
    }

    async resolveLookupDisplayName(recordId) {
        try {
            return await getLookupDisplayName({ recordId });
        } catch (error) {
            return null;
        }
    }

    async handleSave(event) {
        const draftValues = event.detail.draftValues;
        const rowsById = new Map(this.rows.map((r) => [r.recordId, r]));
        const drafts = [];

        for (const draft of draftValues) {
            const row = rowsById.get(draft.recordId);
            if (!row) {
                continue;
            }
            const changedFields = { ...draft };
            delete changedFields.recordId;
            // Client-side mirror of the per-row FLS/sharing gate Apex enforces for real - since
            // lightning-datatable's "editable" is column-level only, a user could still see a
            // pencil on a row they lack access to; strip it here so we don't even attempt the
            // save, rather than relying solely on the server rejecting it.
            for (const [changedField, editableFlag] of Object.entries(EDITABLE_FLAG_BY_FIELD)) {
                if (Object.prototype.hasOwnProperty.call(changedFields, changedField) && !row[editableFlag]) {
                    delete changedFields[changedField];
                }
            }
            if (Object.keys(changedFields).length > 0) {
                drafts.push({ recordId: row.recordId, activityType: row.activityType, changedFields });
            }
        }

        if (drafts.length === 0) {
            this.draftValues = [];
            return;
        }

        this.isSaving = true;
        try {
            const result = await saveActivities({ draftsJson: JSON.stringify(drafts) });
            if (result.success) {
                this.draftValues = [];
                this.showToast('Success', this.labels.saveSuccess, 'success');
                await this.loadActivities(false);
            } else {
                this.showToast('Error', result.errors.join(' ') || this.labels.saveError, 'error');
            }
        } catch (error) {
            this.showToast('Error', this.reduceError(error) || this.labels.saveError, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleCancelEdit() {
        this.draftValues = [];
        // Discard the local display-text previews along with the drafts, so a cancelled edit
        // doesn't leave the new name/date visible in a cell that was never actually changed.
        this.rows = this.pristineRows.map((row) => ({ ...row }));
    }

    getRowActions(row, doneCallback) {
        const actions = [];
        if (row.editableRow) {
            actions.push({ label: 'Edit', name: 'edit' });
        }
        if (row.deletable) {
            actions.push({ label: 'Delete', name: 'delete' });
        }
        if (actions.length === 0) {
            actions.push({ label: 'No actions available', name: 'none', disabled: true });
        }
        doneCallback(actions);
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'edit') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: row.recordId, objectApiName: row.activityType, actionName: 'edit' }
            });
        } else if (actionName === 'delete') {
            this.confirmAndDelete(row);
        }
    }

    async confirmAndDelete(row) {
        const confirmed = await LightningConfirm.open({
            label: this.labels.deleteConfirmTitle,
            message: this.labels.deleteConfirmMessage,
            theme: 'warning'
        });
        if (!confirmed) {
            return;
        }
        try {
            const result = await deleteActivities({
                recordIdsJson: JSON.stringify([row.recordId]),
                activityTypesJson: JSON.stringify([row.activityType])
            });
            if (result.success) {
                this.showToast('Success', this.labels.deleteSuccess, 'success');
                await this.loadActivities(false);
            } else {
                this.showToast('Error', result.errors.join(' '), 'error');
            }
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        }
    }

    handleActivityNavigate(event) {
        const { recordId, objectApiName } = event.detail;
        const attributes = { recordId, actionName: 'view' };
        if (objectApiName) {
            attributes.objectApiName = objectApiName;
        }
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes });
    }

    // Standard record-creation navigation (Salesforce calls this a "headless quick action") -
    // this opens the exact same native "New Task"/"New Event" panel as the global + menu, without
    // a custom-built form. standard__quickAction with a "Global.*" apiName looks like the more
    // direct route but hung indefinitely when actually tried from this component (confirmed via
    // browser testing - it's not a reliably documented path); standard__objectPage + actionName
    // "new" is Salesforce's own documented pattern for this and works correctly. Salesforce owns
    // the resulting panel entirely, so there's no create-completion callback to hook a refresh on;
    // use Refresh (or Apply/re-search/re-sort, which all reload too) after creating a record.
    handleNewTask() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Task', actionName: 'new' }
        });
    }

    handleNewEvent() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Event', actionName: 'new' }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return '';
    }
}