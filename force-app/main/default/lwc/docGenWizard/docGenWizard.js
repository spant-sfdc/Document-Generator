import { LightningElement, track } from 'lwc';

const STEP_LABELS      = ['Upload', 'Object', 'Mapping', 'Variables', 'Preview'];
const EDIT_STEP_LABELS = ['Object', 'Mapping', 'Variables', 'Preview'];
const SESSION_KEY      = 'docgen_wizard_state';
const EDIT_KEY         = 'docgen_edit_state';
const EMPTY_STATE = {
    templateName:             '',
    existingTemplateRecordId: null,
    templateId:               null,
    templateTokens:           [],
    sysTokens:                [],
    variableTokens:           [],
    primaryObject:            null,
    primaryObjectLabel:       '',
    parentObjects:            [],
    childObjects:             [],
    relatedObjects:           [],
    relatedObjectsWithLabels: [],
    tokenMappings:            [],
    variables:                []
};

export default class DocGenWizard extends LightningElement {
    @track currentStep  = 0;
    @track wizardState  = { ...EMPTY_STATE };
    @track _isEditMode  = false;

    stepLabels = STEP_LABELS;

    get activeStepLabels() {
        return this._isEditMode ? EDIT_STEP_LABELS : STEP_LABELS;
    }

    get progressStep() {
        return this._isEditMode ? this.currentStep - 1 : this.currentStep;
    }

    get isEditMode() { return this._isEditMode; }
    get isStep0() { return this.currentStep === 0; }
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }

    get templateConfig() {
        return {
            templateName:             this.wizardState.templateName,
            existingTemplateRecordId: this.wizardState.existingTemplateRecordId,
            templateId:               this.wizardState.templateId,
            primaryObject:            this.wizardState.primaryObject,
            tokenMappings:            this.wizardState.tokenMappings,
            variables:                this.wizardState.variables,
            recordId:                 ''
        };
    }

    connectedCallback() {
        // Edit mode: check for edit context stored by docGenEditButton
        try {
            const editJson = sessionStorage.getItem(EDIT_KEY);
            if (editJson) {
                sessionStorage.removeItem(EDIT_KEY);
                const editState    = JSON.parse(editJson);
                this.wizardState   = { ...EMPTY_STATE, ...editState };
                this._isEditMode   = true;
                this.currentStep   = 1;
                return;
            }
        } catch (e) { /* ignore */ }

        // Normal mode: restore session
        try {
            const saved = sessionStorage.getItem(SESSION_KEY);
            if (saved) {
                const parsed = JSON.parse(saved);
                // Migrate old sessions that used flat relatedObjects
                if (!parsed.parentObjects && parsed.relatedObjectsWithLabels && parsed.relatedObjectsWithLabels.length > 0) {
                    parsed.parentObjects = parsed.relatedObjectsWithLabels;
                    parsed.childObjects  = [];
                }
                this.wizardState = { ...EMPTY_STATE, ...parsed };
            }
        } catch (e) { /* ignore corrupt session */ }
    }

    handleStepComplete(evt) {
        const payload = evt.detail || {};
        let newState  = { ...this.wizardState, ...payload };

        // New template upload invalidates all prior mappings
        if (this.currentStep === 0 && payload.templateId) {
            newState.tokenMappings = [];
            newState.sysTokens     = payload.sysTokens || [];
        }

        this.wizardState = newState;

        // Only persist to sessionStorage in standalone (non-edit) mode
        if (!this._isEditMode) {
            try { sessionStorage.setItem(SESSION_KEY, JSON.stringify(this.wizardState)); } catch (e) {}
        }

        if (this.currentStep < STEP_LABELS.length - 1) {
            this.currentStep++;
        }
    }

    handleBack() {
        // In edit mode, cannot navigate before the Object step (step 1)
        if (this._isEditMode && this.currentStep <= 1) return;
        if (this.currentStep > 0) this.currentStep--;
    }

    handleReset() {
        this.wizardState  = { ...EMPTY_STATE };
        this.currentStep  = 0;
        this._isEditMode  = false;
        try { sessionStorage.removeItem(SESSION_KEY); } catch (e) {}
    }
}
