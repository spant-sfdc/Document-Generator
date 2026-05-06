import { LightningElement, api, track } from 'lwc';
import getFields               from '@salesforce/apex/DocGen_Controller.getFields';
import getParentRelationships  from '@salesforce/apex/DocGen_Controller.getParentRelationships';
import getDemoModeConfig       from '@salesforce/apex/DocGen_Controller.getDemoModeConfig';

const MAPPING_TYPE_OPTIONS = [
    { label: 'Field',    value: 'FIELD'    },
    { label: 'Constant', value: 'CONSTANT' },
    { label: 'Variable', value: 'VARIABLE' }
];

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

    // Cache: 'primaryObj|parentObj' → [{label, relationshipName}]
    _relCache    = {};
    _demoConfig  = null;

    mappingTypeOptions = MAPPING_TYPE_OPTIONS;

    get hasMappings()    { return this.tokenMappings.length > 0; }
    get hasSysTokens()   { return (this.sysTokens || []).length > 0; }
    get isDemoEnabled()  { return !!(this._demoConfig && this._demoConfig.isEnabled); }
    get demoScenario()   { return this._demoConfig ? (this._demoConfig.scenarioName || '') : ''; }

    get sysTokenRows() {
        return (this.sysTokens || []).map(tok => {
            const key = tok.replace('{{', '').replace('}}', '').trim();
            return { token: tok, description: SYS_DESCRIPTIONS[key] || 'Auto-resolved system variable' };
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
        try {
            this._demoConfig = await getDemoModeConfig();
        } catch (e) {
            this._demoConfig = { isEnabled: false };
        }

        await this.preloadFields();

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
                    // Recover the relationship name from the saved path (first segment before '.')
                    let savedRelName = '';
                    if (m.relationshipPath && this._isParent(m.sourceObject)) {
                        savedRelName = m.relationshipPath.split('.')[0] || '';
                    }
                    return {
                        ...m,
                        fieldOptions:              this.buildFieldOptions(obj),
                        isFieldType:               m.mappingType === 'FIELD',
                        isConstantType:            m.mappingType === 'CONSTANT',
                        isParentType:              this._isParent(m.sourceObject),
                        _selectedRelationshipName: savedRelName,
                        _showRelPicker:            false,  // don't re-fetch for saved mappings
                        relationshipOptions:        []
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
                mappingType:               'FIELD',
                sourceObject:              childApi,
                sourceField:               '',
                staticValue:               '',
                formatOverride:            '',
                relationshipPath:          '',
                isRepeating:               true,
                repeatObject:              childApi,
                fieldOptions:              this.buildFieldOptions(childApi),
                isFieldType:               true,
                isConstantType:            false,
                isParentType:              false,
                _selectedRelationshipName: '',
                _showRelPicker:            false,
                relationshipOptions:       []
            };
        }
        return {
            token,
            mappingType:               'FIELD',
            sourceObject:              this.primaryObject,
            sourceField:               '',
            staticValue:               '',
            formatOverride:            '',
            relationshipPath:          '',
            isRepeating:               false,
            repeatObject:              '',
            fieldOptions:              this.buildFieldOptions(this.primaryObject),
            isFieldType:               true,
            isConstantType:            false,
            isParentType:              false,
            _selectedRelationshipName: '',
            _showRelPicker:            false,
            relationshipOptions:       []
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
                try { this.fieldCache[obj] = await getFields({ objectName: obj }); }
                catch (e) { this.fieldCache[obj] = []; }
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

    async _fetchRelationships(parentObject) {
        const cacheKey = `${this.primaryObject}|${parentObject}`;
        if (this._relCache[cacheKey] !== undefined) return this._relCache[cacheKey];
        try {
            const rels = await getParentRelationships({
                primaryObject: this.primaryObject,
                parentObject
            });
            this._relCache[cacheKey] = rels || [];
        } catch (e) {
            this._relCache[cacheKey] = [];
        }
        return this._relCache[cacheKey];
    }

    async handleMappingChange(evt) {
        const token = evt.target.dataset.token;
        const field = evt.target.dataset.field;
        const value = evt.detail.value !== undefined ? evt.detail.value : evt.target.value;

        this.tokenMappings = await Promise.all(this.tokenMappings.map(async m => {
            if (m.token !== token) return m;

            // Don't spread 'selectedRelationship' as a real property — handle it explicitly
            const updated = field === 'selectedRelationship'
                ? { ...m }
                : { ...m, [field]: value };

            if (field === 'sourceObject') {
                if (!this.fieldCache[value]) {
                    try { this.fieldCache[value] = await getFields({ objectName: value }); }
                    catch (e) { this.fieldCache[value] = []; }
                }
                updated.fieldOptions     = this.buildFieldOptions(value);
                updated.sourceField      = '';
                updated.relationshipPath = '';
                updated.isParentType     = this._isParent(value);

                if (updated.isParentType) {
                    const rels = await this._fetchRelationships(value);
                    if (rels.length === 1) {
                        // Single relationship — auto-select, no picker needed
                        updated._selectedRelationshipName = rels[0].relationshipName;
                        updated._showRelPicker            = false;
                        updated.relationshipOptions       = [];
                    } else if (rels.length > 1) {
                        // Multiple relationships — show picker, default to first
                        updated.relationshipOptions       = rels.map(r => ({
                            label: r.label,
                            value: r.relationshipName
                        }));
                        updated._selectedRelationshipName = rels[0].relationshipName;
                        updated._showRelPicker            = true;
                    } else {
                        // No relationships found — fallback to object name (standard case)
                        updated._selectedRelationshipName = value;
                        updated._showRelPicker            = false;
                        updated.relationshipOptions       = [];
                    }
                } else {
                    updated._selectedRelationshipName = '';
                    updated._showRelPicker            = false;
                    updated.relationshipOptions       = [];
                }

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
                    const relName = updated._selectedRelationshipName || updated.sourceObject;
                    updated.relationshipPath = `${relName}.${value}`;
                } else if (!updated.isParentType) {
                    updated.relationshipPath = '';
                }
            }

            if (field === 'selectedRelationship') {
                updated._selectedRelationshipName = value;
                if (updated.sourceField) {
                    updated.relationshipPath = `${value}.${updated.sourceField}`;
                }
            }

            if (field === 'mappingType') {
                updated.isFieldType    = value === 'FIELD';
                updated.isConstantType = value === 'CONSTANT';
            }
            return updated;
        }));
    }

    handleDemoFill() {
        if (!this._demoConfig || !this._demoConfig.autoMappingJson) return;
        let demoMappings;
        try {
            demoMappings = JSON.parse(this._demoConfig.autoMappingJson);
        } catch (e) { return; }

        const byToken = {};
        demoMappings.forEach(m => { byToken[m.token] = m; });

        this.tokenMappings = this.tokenMappings.map(row => {
            const demo = byToken[row.token];
            if (!demo) return row;

            const isParent = this._isParent(demo.sourceObject);
            let relName = '';
            if (isParent && demo.relationshipPath) {
                relName = demo.relationshipPath.split('.')[0];
            }
            const mType = demo.mappingType || 'FIELD';
            return {
                ...row,
                mappingType:               mType,
                sourceObject:              demo.sourceObject,
                sourceField:               demo.sourceField || '',
                staticValue:               demo.staticValue || '',
                formatOverride:            demo.formatOverride || '',
                relationshipPath:          demo.relationshipPath || '',
                isRepeating:               !!demo.isRepeating,
                repeatObject:              demo.repeatObject || '',
                fieldOptions:              this.buildFieldOptions(demo.sourceObject),
                isFieldType:               mType === 'FIELD',
                isConstantType:            mType === 'CONSTANT',
                isParentType:              isParent,
                _selectedRelationshipName: relName,
                _showRelPicker:            false,
                relationshipOptions:       []
            };
        });
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
