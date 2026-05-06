import { LightningElement, api, track } from 'lwc';
import getDemoModeConfig from '@salesforce/apex/DocGen_Controller.getDemoModeConfig';

const TYPE_OPTIONS = [
    { label: 'Boolean (Expression)', value: 'BOOLEAN' },
    { label: 'Text (Static)',        value: 'TEXT'     },
    { label: 'Number',               value: 'NUMBER'   },
    { label: 'Date',                 value: 'DATE'     }
];

const SYSTEM_VARIABLES = [
    { token: '{{sys.today}}',       description: "Today's date" },
    { token: '{{sys.currentUser}}', description: 'Running user full name' },
    { token: '{{sys.orgName}}',     description: 'Org display name (DocGen Config)' },
    { token: '{{sys.userEmail}}',   description: 'Running user email' },
    { token: '{{sys.orgEIN}}',      description: 'Org EIN (DocGen Config)' },
    { token: '{{sys.orgAddress}}',  description: 'Org address (DocGen Config)' },
    { token: '{{sys.orgPhone}}',    description: 'Org phone (DocGen Config)' },
    { token: '{{sys.orgWebsite}}',  description: 'Org website (DocGen Config)' }
];

// Map legacy backend types to new UI types
const LEGACY_TYPE_MAP = { 'EXPRESSION': 'BOOLEAN', 'CONSTANT': 'TEXT' };

let _idSeq = 0;
function uid() { return 'var_' + (++_idSeq); }

export default class DocGenVariablesPanel extends LightningElement {
    @api variableTokens = [];
    @api savedVariables = [];

    @track rows = [];

    typeOptions     = TYPE_OPTIONS;
    systemVariables = SYSTEM_VARIABLES;
    _demoConfig     = null;

    get hasRows()       { return this.rows.length > 0; }
    get rowCount()      { return this.rows.length; }
    get isDemoEnabled() { return !!(this._demoConfig && this._demoConfig.isEnabled); }
    get demoScenario()  { return this._demoConfig ? (this._demoConfig.scenarioName || '') : ''; }

    async connectedCallback() {
        try {
            this._demoConfig = await getDemoModeConfig();
        } catch (e) {
            this._demoConfig = { isEnabled: false };
        }

        const savedByName = {};
        (this.savedVariables || []).forEach(v => {
            if (v.variableName) savedByName[v.variableName] = v;
        });

        const rows  = [];
        const seen  = new Set();

        // Auto-detected variables from {{#if ...}} blocks — default to BOOLEAN
        (this.variableTokens || []).forEach(name => {
            seen.add(name);
            const saved = savedByName[name];
            rows.push(this._makeRow(
                name,
                saved ? (LEGACY_TYPE_MAP[saved.variableType] || saved.variableType || 'BOOLEAN') : 'BOOLEAN',
                saved ? (saved.expression || saved.staticValue || '') : '',
                true
            ));
        });

        // Previously saved variables not in the auto-detected list
        (this.savedVariables || []).forEach(v => {
            if (!seen.has(v.variableName)) {
                const mappedType = LEGACY_TYPE_MAP[v.variableType] || v.variableType || 'BOOLEAN';
                rows.push(this._makeRow(
                    v.variableName,
                    mappedType,
                    v.expression || v.staticValue || '',
                    false
                ));
            }
        });

        this.rows = rows;
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleDemoFillVariables() {
        if (!this._demoConfig || !this._demoConfig.autoVariablesJson) return;
        let demoVars;
        try {
            demoVars = JSON.parse(this._demoConfig.autoVariablesJson);
        } catch (e) { return; }

        const seen = new Set();
        // Update expression/type on existing rows that match a demo variable
        const updated = this.rows.map(row => {
            const demo = demoVars.find(d => d.variableName === row.variableName);
            if (demo) {
                seen.add(demo.variableName);
                return this._makeRow(
                    row.variableName,
                    demo.variableType || row.variableType,
                    demo.expression   || '',
                    row.autoDetected
                );
            }
            return row;
        });
        // Append any demo variables not already present
        demoVars.forEach(d => {
            if (!seen.has(d.variableName)) {
                updated.push(this._makeRow(d.variableName, d.variableType || 'BOOLEAN', d.expression || '', false));
            }
        });
        this.rows = updated;
    }

    handleAddRow() {
        this.rows = [...this.rows, this._makeRow('', 'BOOLEAN', '', false)];
    }

    handleRemoveRow(evt) {
        const id = evt.currentTarget.dataset.id;
        this.rows = this.rows.filter(r => r._id !== id);
        this._clearDuplicateErrors();
    }

    handleNameChange(evt) {
        const id    = evt.currentTarget.dataset.id;
        const value = evt.target.value;
        this.rows = this.rows.map(r => r._id === id
            ? this._withoutError({ ...r, variableName: value })
            : r
        );
        this._clearDuplicateErrors();
    }

    handleTypeChange(evt) {
        const id    = evt.currentTarget.dataset.id;
        const value = evt.detail.value;
        this.rows = this.rows.map(r =>
            r._id === id
                ? this._withoutError({
                    ...r,
                    variableType:          value,
                    isBoolean:             value === 'BOOLEAN',
                    expressionPlaceholder: value === 'BOOLEAN' ? 'e.g. Amount > 10000' : 'Static value'
                })
                : r
        );
    }

    handleExpressionChange(evt) {
        const id    = evt.currentTarget.dataset.id;
        const value = evt.target.value;
        this.rows = this.rows.map(r => r._id === id
            ? this._withoutError({ ...r, expression: value })
            : r
        );
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('stepback', { bubbles: true, composed: true }));
    }

    handleNext() {
        // Validate — mark errors but don't clear them until user fixes
        let hasErrors = false;
        const nameCounts = {};
        this.rows.forEach(r => {
            const nm = (r.variableName || '').trim();
            if (nm) nameCounts[nm] = (nameCounts[nm] || 0) + 1;
        });

        this.rows = this.rows.map(r => {
            const nm = (r.variableName || '').trim();
            if (!nm) return r; // blank name rows are ignored

            if (nameCounts[nm] > 1) {
                hasErrors = true;
                return this._withError(r, 'Duplicate variable name');
            }
            if (r.variableType === 'BOOLEAN' && !(r.expression || '').trim()) {
                hasErrors = true;
                return this._withError(r, 'Expression required for Boolean variables');
            }
            return this._withoutError(r);
        });

        if (hasErrors) return;

        const variables = this.rows
            .filter(r => r.variableName && r.variableName.trim())
            .map(r => ({
                variableName:   r.variableName.trim(),
                variableType:   r.variableType,
                // Store expression in staticValue so existing Static_Value__c field holds it
                staticValue:    r.expression,
                expression:     r.variableType === 'BOOLEAN' ? r.expression : null,
                imageVersionId: null
            }));

        this.dispatchEvent(new CustomEvent('stepcomplete', {
            bubbles:  true,
            composed: true,
            detail:   { variables }
        }));
    }

    // ── Private ───────────────────────────────────────────────────────────────

    _makeRow(name, type, expression, autoDetected) {
        const safeType = TYPE_OPTIONS.some(o => o.value === type) ? type : 'BOOLEAN';
        return {
            _id:                   uid(),
            variableName:          name,
            variableType:          safeType,
            expression:            expression,
            isBoolean:             safeType === 'BOOLEAN',
            expressionPlaceholder: safeType === 'BOOLEAN' ? 'e.g. Amount > 10000' : 'Static value',
            autoDetected,
            hasError:              false,
            errorMessage:          '',
            rowClass:              '',   // 'var-row-error' when hasError
            inputClass:            ''    // 'input-error' when hasError
        };
    }

    _withError(row, message) {
        return { ...row, hasError: true, errorMessage: message, rowClass: 'var-row-error', inputClass: 'input-error' };
    }

    _withoutError(row) {
        return { ...row, hasError: false, errorMessage: '', rowClass: '', inputClass: '' };
    }

    _clearDuplicateErrors() {
        const nameCounts = {};
        this.rows.forEach(r => {
            const nm = (r.variableName || '').trim();
            if (nm) nameCounts[nm] = (nameCounts[nm] || 0) + 1;
        });
        this.rows = this.rows.map(r => {
            const nm = (r.variableName || '').trim();
            if (r.hasError && r.errorMessage === 'Duplicate variable name') {
                return nameCounts[nm] > 1 ? r : this._withoutError(r);
            }
            return r;
        });
    }
}
