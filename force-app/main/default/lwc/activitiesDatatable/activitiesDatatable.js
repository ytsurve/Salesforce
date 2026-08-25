import LightningDatatable from 'lightning/datatable';
import activityIndicatorView from './activityIndicatorView.html';
import activityLinkView from './activityLinkView.html';
import activityLinkEdit from './activityLinkEdit.html';
import activityLookupEdit from './activityLookupEdit.html';
import activityDateView from './activityDateView.html';
import activityDateEdit from './activityDateEdit.html';

export default class ActivitiesDatatable extends LightningDatatable {
    static customTypes = {
        activityIndicator: {
            template: activityIndicatorView,
            standardCellLayout: true,
            typeAttributes: ['iconName', 'label', 'recordId', 'objectApiName']
        },
        // Subject: a clickable link in view mode, plain text input in edit mode.
        activityLink: {
            template: activityLinkView,
            editTemplate: activityLinkEdit,
            standardCellLayout: true,
            typeAttributes: ['recordId', 'objectApiName', 'displayName', 'url']
        },
        // Related To / Name / Assigned To: same clickable-link view as activityLink, but edited
        // via a lookup picker (lookupCellEditor) instead of free text, since these are reference
        // fields (WhatId/WhoId/OwnerId) rather than plain strings.
        activityLookupLink: {
            template: activityLinkView,
            editTemplate: activityLookupEdit,
            standardCellLayout: true,
            typeAttributes: ['recordId', 'objectApiName', 'displayName', 'url', 'objectOptions']
        },
        activityDate: {
            template: activityDateView,
            editTemplate: activityDateEdit,
            standardCellLayout: true,
            typeAttributes: ['displayValue', 'dateOnly']
        }
    };

    handleNavigate(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.recordId;
        const objectApiName = event.currentTarget.dataset.objectApiName;
        if (!recordId) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('activitynavigate', {
                detail: { recordId, objectApiName },
                bubbles: true,
                composed: true
            })
        );
    }

    handleNavigateKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            this.handleNavigate(event);
        }
    }
}
