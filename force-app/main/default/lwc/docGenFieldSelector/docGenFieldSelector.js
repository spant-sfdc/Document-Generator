import { LightningElement, api, track } from 'lwc';
import getFields from '@salesforce/apex/DocGen_Controller.getFields';

export default class DocGenFieldSelector extends LightningElement {
    @api primaryObject  = null;
    @api relatedObjects = [];

    @track objectTabs     = [];
    @track selectedFields = {};
    @track isLoading      = false;
    @track error          = null;

    async connectedCallback() {
        this.isLoading = true;
        try {
            const allObjects = [this.primaryObject, ...(this.relatedObjects || [])].filter(Boolean);
            const tabs = [];
            for (const obj of allObjects) {
                const fields = await getFields({ objectName: obj });
                tabs.push({ objectName: obj, label: obj, fields });
                this.selectedFields[obj] = [];
            }
            this.objectTabs = tabs;
        } catch (e) {
            this.error = e;
        } finally {
            this.isLoading = false;
        }
    }

    handleFieldSelectionChanged(evt) {
        const { objectName, selectedFields } = evt.detail;
        this.selectedFields = { ...this.selectedFields, [objectName]: selectedFields };
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('stepback', { bubbles: true, composed: true }));
    }

    handleNext() {
        this.dispatchEvent(new CustomEvent('stepcomplete', {
            bubbles: true,
            composed: true,
            detail: { selectedFields: { ...this.selectedFields } }
        }));
    }
}
