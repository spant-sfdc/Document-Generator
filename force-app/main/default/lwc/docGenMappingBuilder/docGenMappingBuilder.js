import { LightningElement, api, track } from 'lwc';
import getFields from '@salesforce/apex/DocGen_Controller.getFields';

const MAPPING_TYPE_OPTIONS = [
    { label: 'Field',    value: 'FIELD'    },
    { label: 'Constant', value: 'CONSTANT' },
    { label: 'Variable', value: 'VARIABLE' }
];

// Static descriptions for the sys.* namespace — shown as read-only reference rows
const SYS_DESCRIPTIONS = {
    'sys.today':       "Today's date",
    'sys.currentUser': 'Running user full name',
    'sys.orgName':     'Org display name (DocGen Config or Salesforce org name)',
    'sys.userEmail':   'Running user email address',
    'sys.orgEIN':      'Federal EIN — set in DocGen Config custom metadata',
    'sys.orgAddress':  'Org address — set in DocGen Config custom metadata',
    'sys.orgPhone':    'Org phone — set in DocGen Config custom metadata',
    'sys.orgWebsite':  'Org website — set in DocGen Config custom metadata'
};

export default class DocGenMappingBuilder extends LightningElement {
    @api templateTokens = [];
    @api primaryObject  = null;
    @api parentObjects  = [];
    @api childObjects   = [];
    @api savedMappings  = [];
    @api sysTokens      = [];

    @track tokenMappings = [];
    @track fieldCache    = {};
    @track error         = null;

    mappingTypeOptions = MAPPING_TYPE_OPTIONS;

    get hasMappings()    { return this.tokenMappings.length > 0; }
    get hasSysTokens()   { return (this.sysTokens || []).length > 0; }

    get sysTokenRows() {
        return (this.sysTokens || []).map(tok => {
            const key = tok.replace('{{', '').replace('}}', '').trim();
            return {
                token:       tok,
                description: SYS_DESCRIPTIONS[key] || 'Auto-resolved system variable'
            };
        });
    }

    get objectOptions() {
        const opts = [];
        if (this.primaryObject) {
            opts.push({ label: `${this.primaryObject} (Primary)`, value: this.primaryObject });
        }
        (this.parentObjects || []).forEach(p => {
            opts.push({ label: `${p.label || p.apiName} (Parent)`, value: p.apiName });
        });
        (this.childObjects || []).forEach(c => {
            opts.push({ label: `${c.label || c.apiName} (Child)`, value: c.apiName });
        });
        return opts;
    }

    async connectedCallback() {
        await this.preloadFields();

        // savedMappings supplies pre-filled values; templateTokens is the canonical list
        const savedByToken = {};
        (this.savedMappings || []).forEach(m => { if (m.token) savedByToken[m.token] = m; });

        this.tokenMappings = await Promise.all(
            (this.templateTokens || []).map(async token => {
                if (savedByToken[token]) {
                    const m   = savedByToken[token];
                    const obj = m.sourceObject || this.primaryObject;
                    if (obj && !this.fieldCache[obj]) {
                        try { this.fieldCache[obj] = await getFields({ objectName: obj }); }
                        catch (e) { this.fieldCache[obj] = []; }
                    }
                    return {
                        ...m,
                        fieldOptions:   this.buildFieldOptions(obj),
                        isFieldType:    m.mappingType === 'FIELD',
                        isConstantType: m.mappingType === 'CONSTANT',
                        isParentType:   this._isParent(m.sourceObject)
                    };
                }
                return this._buildFreshMapping(token);
            })
        );
    }

    _buildFreshMapping(token) {
        const isSectionOpen = token.startsWith('{{#');
        if (isSectionOpen) {
            const sectionName  = token.replace('{{#', '').replace('}}', '').trim();
            const matchedChild = (this.childObjects || []).find(
                c => c.apiName.toLowerCase() === sectionName.toLowerCase()
            );
            const childApi = matchedChild
                ? matchedChild.apiName
                : ((this.childObjects || [])[0] ? this.childObjects[0].apiName : this.primaryObject);
            return {
                token,
                mappingType:      'FIELD',
                sourceObject:     childApi,
                sourceField:      '',
                staticValue:      '',
                formatOverride:   '',
                relationshipPath: '',
                isRepeating:      true,
                repeatObject:     childApi,
                fieldOptions:     this.buildFieldOptions(childApi),
                isFieldType:      true,
                isConstantType:   false,
                isParentType:     false
            };
        }
        return {
            token,
            mappingType:      'FIELD',
            sourceObject:     this.primaryObject,
            sourceField:      '',
            staticValue:      '',
            formatOverride:   '',
            relationshipPath: '',
            isRepeating:      false,
            repeatObject:     '',
            fieldOptions:     this.buildFieldOptions(this.primaryObject),
            isFieldType:      true,
            isConstantType:   false,
            isParentType:     false
        };
    }

    async preloadFields() {
        const allObjects = [
            this.primaryObject,
            ...(this.parentObjects || []).map(p => p.apiName),
            ...(this.childObjects  || []).map(c => c.apiName)
        ].filter(Boolean);
        for (const obj of allObjects) {
            if (!this.fieldCache[obj]) {
                try {
                    this.fieldCache[obj] = await getFields({ objectName: obj });
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

    _isParent(apiName) {
        return (this.parentObjects || []).some(p => p.apiName === apiName);
    }

    _isChild(apiName) {
        return (this.childObjects || []).some(c => c.apiName === apiName);
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
                        this.fieldCache[value] = await getFields({ objectName: value });
                    } catch (e) { this.fieldCache[value] = []; }
                }
                updated.fieldOptions      = this.buildFieldOptions(value);
                updated.sourceField       = '';
                updated.relationshipPath  = '';
                updated.isParentType      = this._isParent(value);
                if (this._isChild(value)) {
                    updated.isRepeating  = true;
                    updated.repeatObject = value;
                } else {
                    updated.isRepeating  = false;
                    updated.repeatObject = '';
                }
            }

            if (field === 'sourceField') {
                if (updated.isParentType && value) {
                    updated.relationshipPath = `${updated.sourceObject}.${value}`;
                } else if (!updated.isParentType) {
                    updated.relationshipPath = '';
                }
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
            token:            m.token,
            sourceObject:     m.sourceObject,
            sourceField:      m.sourceField,
            relationshipPath: m.relationshipPath || '',
            mappingType:      m.mappingType,
            staticValue:      m.staticValue,
            formatOverride:   m.formatOverride,
            isRepeating:      m.isRepeating,
            repeatObject:     m.repeatObject
        }));
        this.dispatchEvent(new CustomEvent('stepcomplete', {
            bubbles:  true,
            composed: true,
            detail:   { tokenMappings: mappings }
        }));
    }
}
