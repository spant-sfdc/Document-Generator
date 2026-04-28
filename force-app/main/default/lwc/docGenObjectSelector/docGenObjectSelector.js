import { LightningElement, api, track, wire } from 'lwc';
import getObjects from '@salesforce/apex/DocGen_Controller.getObjects';

export default class DocGenObjectSelector extends LightningElement {
    @api savedPrimaryObject = null;
    @api savedPrimaryLabel  = '';
    @api savedRelated       = [];

    @track allObjects       = [];
    @track suggestions      = [];
    @track showSuggestions  = false;
    @track searchTerm       = '';
    @track primaryObject    = null;
    @track primaryLabel     = '';
    @track relatedObjects   = [];
    @track isLoading        = true;
    @track error            = null;

    _debounceTimer = null;

    get isNextDisabled()    { return !this.primaryObject || this.isLoading; }
    get hasRelated()        { return this.relatedObjects.length > 0; }
    get searchPlaceholder() {
        return this.primaryObject
            ? 'Search to add a related object...'
            : 'Type an object name to search...';
    }

    connectedCallback() {
        if (this.savedPrimaryObject) {
            this.primaryObject = this.savedPrimaryObject;
            this.primaryLabel  = this.savedPrimaryLabel || this.savedPrimaryObject;
        }
        if (this.savedRelated && this.savedRelated.length > 0) {
            this.relatedObjects = this.savedRelated.map(r =>
                typeof r === 'object' ? r : { apiName: r, label: r }
            );
        }
    }

    @wire(getObjects)
    wiredObjects({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.allObjects = data;
        } else if (error) {
            this.error = error;
        }
    }

    handleSearchInput(evt) {
        this.searchTerm = evt.target.value;
        clearTimeout(this._debounceTimer);
        this._debounceTimer = setTimeout(() => {
            this._filterSuggestions(this.searchTerm);
        }, 300);
    }

    _filterSuggestions(term) {
        if (!term || term.trim().length < 1) {
            this.suggestions     = [];
            this.showSuggestions = false;
            return;
        }
        const lower = term.toLowerCase();
        const alreadySelected = new Set(
            [this.primaryObject, ...this.relatedObjects.map(r => r.apiName)].filter(Boolean)
        );
        this.suggestions = this.allObjects
            .filter(o =>
                !alreadySelected.has(o.apiName) &&
                (o.label.toLowerCase().includes(lower) || o.apiName.toLowerCase().includes(lower))
            )
            .slice(0, 10);
        this.showSuggestions = this.suggestions.length > 0;
    }

    handleSelectSuggestion(evt) {
        const apiName = evt.currentTarget.dataset.apiName;
        const label   = evt.currentTarget.dataset.label;

        if (!this.primaryObject) {
            this.primaryObject = apiName;
            this.primaryLabel  = label;
        } else {
            this.relatedObjects = [...this.relatedObjects, { apiName, label }];
        }
        this.searchTerm      = '';
        this.suggestions     = [];
        this.showSuggestions = false;
        this.template.querySelector('.search-input').value = '';
    }

    handleRemovePrimary() {
        this.primaryObject  = null;
        this.primaryLabel   = '';
        this.relatedObjects = [];
    }

    handleRemoveRelated(evt) {
        const apiName = evt.currentTarget.dataset.apiName;
        this.relatedObjects = this.relatedObjects.filter(r => r.apiName !== apiName);
    }

    handleSearchBlur() {
        // Delay hide so click on suggestion fires first
        setTimeout(() => {
            this.showSuggestions = false;
        }, 200);
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('stepback', { bubbles: true, composed: true }));
    }

    handleNext() {
        this.dispatchEvent(new CustomEvent('stepcomplete', {
            bubbles: true,
            composed: true,
            detail: {
                primaryObject:            this.primaryObject,
                primaryObjectLabel:        this.primaryLabel,
                relatedObjects:            this.relatedObjects.map(r => r.apiName),
                relatedObjectsWithLabels:  this.relatedObjects.map(r => ({ apiName: r.apiName, label: r.label }))
            }
        }));
    }
}
