import { LightningElement, api, track } from 'lwc';
import searchObjects from '@salesforce/apex/DocGen_Controller.searchObjects';

export default class DocGenObjectSelector extends LightningElement {
    @api templateTokens     = [];
    @api savedPrimaryObject = null;
    @api savedPrimaryLabel  = '';
    @api savedParentObjects = [];
    @api savedChildObjects  = [];

    @track suggestions     = [];
    @track showSuggestions = false;
    @track primaryObject   = null;
    @track primaryLabel    = '';
    @track parentObjects   = [];
    @track childObjects    = [];
    @track isSearching     = false;
    @track error           = null;
    @track childWarning    = null;

    _addMode       = 'PARENT';
    _debounceTimer = null;

    get isNextDisabled()  { return !this.primaryObject || this.isSearching; }
    get hasParents()      { return this.parentObjects.length > 0; }
    get hasChildren()     { return this.childObjects.length > 0; }
    get showModeToggle()  { return !!this.primaryObject; }
    get parentModeClass() { return `mode-btn${this._addMode === 'PARENT' ? ' active-parent' : ''}`; }
    get childModeClass()  { return `mode-btn${this._addMode === 'CHILD'  ? ' active-child'  : ''}`; }
    get searchPlaceholder() {
        if (!this.primaryObject) return 'Type 2+ characters to search primary object...';
        return this._addMode === 'PARENT'
            ? 'Search to add a parent object (lookup from primary)...'
            : 'Search to add a child object (has repeating rows in template)...';
    }

    connectedCallback() {
        if (this.savedPrimaryObject) {
            this.primaryObject = this.savedPrimaryObject;
            this.primaryLabel  = this.savedPrimaryLabel || this.savedPrimaryObject;
        }
        if (this.savedParentObjects && this.savedParentObjects.length > 0) {
            this.parentObjects = this.savedParentObjects.map(r =>
                typeof r === 'object' ? r : { apiName: r, label: r }
            );
        }
        if (this.savedChildObjects && this.savedChildObjects.length > 0) {
            this.childObjects = this.savedChildObjects.map(r =>
                typeof r === 'object' ? r : { apiName: r, label: r }
            );
        }
    }

    handleSearchInput(evt) {
        const term = evt.target.value || '';
        clearTimeout(this._debounceTimer);
        if (term.trim().length < 2) {
            this.suggestions     = [];
            this.showSuggestions = false;
            return;
        }
        this._debounceTimer = setTimeout(() => {
            this._search(term.trim());
        }, 300);
    }

    async _search(term) {
        this.isSearching = true;
        this.error       = null;
        try {
            const results = await searchObjects({ searchTerm: term });
            const taken   = new Set([
                this.primaryObject,
                ...this.parentObjects.map(r => r.apiName),
                ...this.childObjects.map(r  => r.apiName)
            ].filter(Boolean));
            this.suggestions     = (results || []).filter(o => !taken.has(o.apiName));
            this.showSuggestions = this.suggestions.length > 0;
        } catch (e) {
            this.error           = e;
            this.suggestions     = [];
            this.showSuggestions = false;
        } finally {
            this.isSearching = false;
        }
    }

    handleSelectSuggestion(evt) {
        const apiName = evt.currentTarget.dataset.apiName;
        const label   = evt.currentTarget.dataset.label;

        if (!this.primaryObject) {
            this.primaryObject = apiName;
            this.primaryLabel  = label;
        } else if (this._addMode === 'PARENT') {
            this.parentObjects = [...this.parentObjects, { apiName, label }];
        } else {
            this.childObjects = [...this.childObjects, { apiName, label }];
            this._validateChildObjects();
        }
        this.suggestions     = [];
        this.showSuggestions = false;
        this.template.querySelector('.search-input').value = '';
    }

    handleRemovePrimary() {
        this.primaryObject = null;
        this.primaryLabel  = '';
        this.parentObjects = [];
        this.childObjects  = [];
        this.childWarning  = null;
        this._addMode      = 'PARENT';
    }

    handleRemoveParent(evt) {
        const apiName = evt.currentTarget.dataset.apiName;
        this.parentObjects = this.parentObjects.filter(r => r.apiName !== apiName);
    }

    handleRemoveChild(evt) {
        const apiName = evt.currentTarget.dataset.apiName;
        this.childObjects = this.childObjects.filter(r => r.apiName !== apiName);
        this._validateChildObjects();
    }

    handleSetModeParent() { this._addMode = 'PARENT'; }
    handleSetModeChild()  { this._addMode = 'CHILD'; }

    handleSearchBlur() {
        setTimeout(() => { this.showSuggestions = false; }, 200);
    }

    _validateChildObjects() {
        if (this.childObjects.length === 0) { this.childWarning = null; return; }
        const sectionNames = (this.templateTokens || [])
            .filter(t => t.startsWith('{{#'))
            .map(t => t.replace('{{#', '').replace('}}', '').trim().toLowerCase());
        const unmatched = this.childObjects.filter(c =>
            !sectionNames.some(s => s === c.apiName.toLowerCase())
        );
        this.childWarning = unmatched.length > 0
            ? `No repeating section found for: ${unmatched.map(c => c.label).join(', ')}. ` +
              `Add {{#ApiName}}...{{/ApiName}} blocks to your template or remove these objects.`
            : null;
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('stepback', { bubbles: true, composed: true }));
    }

    handleNext() {
        this._validateChildObjects();
        this.dispatchEvent(new CustomEvent('stepcomplete', {
            bubbles: true,
            composed: true,
            detail: {
                primaryObject:            this.primaryObject,
                primaryObjectLabel:       this.primaryLabel,
                parentObjects:            this.parentObjects,
                childObjects:             this.childObjects,
                relatedObjects:           [...this.parentObjects, ...this.childObjects].map(r => r.apiName),
                relatedObjectsWithLabels: [...this.parentObjects, ...this.childObjects]
            }
        }));
    }
}
