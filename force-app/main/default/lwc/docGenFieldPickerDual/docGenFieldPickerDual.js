import { LightningElement, api, track } from 'lwc';

export default class DocGenFieldPickerDual extends LightningElement {
    @api objectName = '';
    @api objectLabel = '';
    @api fields = [];
    @track selectedValues = [];

    get fieldOptions() {
        return (this.fields || []).map(f => ({
            label: `${f.label} (${f.apiName}) — ${f.fieldType}`,
            value: f.apiName
        }));
    }

    handleChange(evt) {
        this.selectedValues = evt.detail.value;
        this.dispatchEvent(new CustomEvent('fieldselectionchanged', {
            bubbles: true,
            composed: true,
            detail: {
                objectName: this.objectName,
                selectedFields: this.selectedValues
            }
        }));
    }
}
