import { LightningElement, api } from 'lwc';

/**
 * Inline-edit widget for a polymorphic lookup cell (Related To / Name / Assigned To) inside
 * c-activities-datatable. Implements the value/validity/showHelpMessageIfInvalid/focus contract
 * lightning-datatable's custom editable types require from whatever element carries
 * data-inputable="true" - here that's this whole component, not the inner record picker, so it's
 * free to wrap extra markup (the object-type selector) alongside the picker.
 */
export default class LookupCellEditor extends LightningElement {
    @api objectOptions = [];
    @api currentObjectApiName;
    @api required = false;

    _value;
    selectedObjectApiName;
    touchedInvalid = false;

    connectedCallback() {
        // If the record's current related-object type isn't one of the offered options (e.g. a
        // Task owned by a Queue when only "User" is offered for Assigned To), fall back to the
        // first option rather than pointing the picker at a type it can't search.
        const currentIsSupported = this.objectOptions.some((opt) => opt.value === this.currentObjectApiName);
        this.selectedObjectApiName = currentIsSupported
            ? this.currentObjectApiName
            : this.objectOptions.length
            ? this.objectOptions[0].value
            : undefined;
    }

    @api
    get value() {
        return this._value;
    }
    set value(val) {
        this._value = val;
    }

    get showObjectSelector() {
        return this.objectOptions && this.objectOptions.length > 1;
    }

    get selectOptions() {
        return this.objectOptions.map((opt) => ({
            ...opt,
            selected: opt.value === this.selectedObjectApiName
        }));
    }

    get recordPickerLabel() {
        const match = this.objectOptions.find((opt) => opt.value === this.selectedObjectApiName);
        return match ? match.label : 'Search';
    }

    get showError() {
        return this.touchedInvalid && this.required && !this._value;
    }

    handleObjectTypeChange(event) {
        this.selectedObjectApiName = event.target.value;
        this._value = null;
    }

    handleRecordChange(event) {
        this._value = event.detail.recordId || null;
        this.touchedInvalid = false;
    }

    @api
    get validity() {
        const valid = !(this.required && !this._value);
        return { valid, valueMissing: !valid };
    }

    @api
    showHelpMessageIfInvalid() {
        this.touchedInvalid = true;
    }

    @api
    focus() {
        const picker = this.template.querySelector('lightning-record-picker');
        if (picker) {
            picker.focus();
        }
    }
}
