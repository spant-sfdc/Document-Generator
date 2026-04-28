import { LightningElement, track } from 'lwc';

const STEP_LABELS  = ['Upload', 'Object', 'Mapping', 'Variables', 'Preview'];
const SESSION_KEY  = 'docgen_wizard_state';
const EMPTY_STATE  = {
    templateId:              null,
    templateTokens:          [],
    primaryObject:           null,
    primaryObjectLabel:      '',
    relatedObjects:          [],
    relatedObjectsWithLabels:[],
    tokenMappings:           [],
    variables:               []
};

export default class DocGenWizard extends LightningElement {
    @track currentStep = 0;
    @track wizardState = { ...EMPTY_STATE };

    stepLabels = STEP_LABELS;

    connectedCallback() {
        try {
            const saved = sessionStorage.getItem(SESSION_KEY);
            if (saved) {
                const parsed = JSON.parse(saved);
                this.wizardState = { ...EMPTY_STATE, ...parsed };
            }
        } catch (e) { /* ignore corrupt session */ }
    }

    get isStep0() { return this.currentStep === 0; }
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }

    get templateConfig() {
        return {
            templateId:    this.wizardState.templateId,
            primaryObject: this.wizardState.primaryObject,
            tokenMappings: this.wizardState.tokenMappings,
            variables:     this.wizardState.variables,
            recordId:      ''
        };
    }

    handleStepComplete(evt) {
        const payload = evt.detail || {};
        this.wizardState = { ...this.wizardState, ...payload };
        try { sessionStorage.setItem(SESSION_KEY, JSON.stringify(this.wizardState)); } catch(e) {}
        if (this.currentStep < STEP_LABELS.length - 1) {
            this.currentStep++;
        }
    }

    handleBack() {
        if (this.currentStep > 0) this.currentStep--;
    }

    handleReset() {
        this.wizardState = { ...EMPTY_STATE };
        this.currentStep = 0;
        try { sessionStorage.removeItem(SESSION_KEY); } catch(e) {}
    }
}
