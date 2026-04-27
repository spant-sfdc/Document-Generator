import { LightningElement, api, track } from 'lwc';
import getFields from '@salesforce/apex/DocGen_Controller.getFields';

const MAPPING_TYPE_OPTIONS = [
    { label: 'Field', value: 'FIELD' },
    { label: 'Constant', value: 'CONSTANT' },
    { label: 'Variable', value: 'VARIABLE' }
];

export default class DocGenMappingBuilder extends LightningElement {
    @api templateTokens  = [];
    @api primaryObject   = null;
    @api relatedObjects  = [];
    @api selectedFields  = {};

    @track tokenMappings = [];
    @track fieldCache    = {};
    @track error         = null;

    mappingTypeOptions = MAPPING_TYPE_OPTIONS;

    get hasMappings() { return this.tokenMappings.length > 0; }

    get objectOptions() {
        const objs = [this.primaryObject, ...(this.relatedObjects || [])].filter(Boolean);
        return objs.map(o => ({ label: o, value: o }));
    }

    async connectedCallback() {
        await this.preloadFields();
        this.tokenMappings = (this.templateTokens || []).map(token => ({
            token,
            mappingType:    'FIELD',
            sourceObject:   this.primaryObject,
            sourceField:    '',
            staticValue:    '',
            formatOverride: '',
            isRepeating:    false,
            repeatObject:   '',
            fieldOptions:   this.buildFieldOptions(this.primaryObject),
            isFieldType:    true,
            isConstantType: false
        }));
    }

    async preloadFields() {
        const allObjects = [this.primaryObject, ...(this.relatedObjects || [])].filter(Boolean);
        for (const obj of allObjects) {
            if (!this.fieldCache[obj]) {
                try {
                    const fields = await getFields({ objectName: obj });
                    this.fieldCache[obj] = fields;
                } catch (e) {
                    this.fieldCache[obj] = [];
                }
            }
        }
    }

    buildFieldOptions(objectName) {
        const fields = this.fieldCache[objectName] || [];
        return fields.map(f => ({ label: `${f.label} (${f.apiName})`, value: f.apiName }));
    }

    async handleMappingChange(evt) {
        const token = evt.target.dataset.token;
        const field = evt.target.dataset.field;
        const value = evt.detail.value !== undefined ? evt.detail.value : evt.target.value;

        this.tokenMappings = await Promise.all(this.tokenMappings.map(async m => {
            if (m.token !== token) return m;
            const updated = { ...m, [field]: value };

            if (field === 'sourceObject') {
                if (!this.fieldCache[value]) {
                    try {
                        const f = await getFields({ objectName: value });
                        this.fieldCache[value] = f;
                    } catch (e) { this.fieldCache[value] = []; }
                }
                updated.fieldOptions = this.buildFieldOptions(value);
                updated.sourceField  = '';
            }
            if (field === 'mappingType') {
                updated.isFieldType    = value === 'FIELD';
                updated.isConstantType = value === 'CONSTANT';
            }
            return updated;
        }));
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('stepback', { bubbles: true, composed: true }));
    }

    handleNext() {
        const mappings = this.tokenMappings.map(m => ({
            token:          m.token,
            sourceObject:   m.sourceObject,
            sourceField:    m.sourceField,
            relationshipPath: '',
            mappingType:    m.mappingType,
            staticValue:    m.staticValue,
            formatOverride: m.formatOverride,
            isRepeating:    m.isRepeating,
            repeatObject:   m.repeatObject
        }));
        this.dispatchEvent(new CustomEvent('stepcomplete', {
            bubbles: true,
            composed: true,
            detail: { tokenMappings: mappings }
        }));
    }
}
