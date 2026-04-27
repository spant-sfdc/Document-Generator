import { LightningElement, track } from 'lwc';

const STEP_LABELS = ['Upload', 'Object', 'Mapping', 'Variables', 'Preview'];

export default class DocGenWizard extends LightningElement {
    @track currentStep = 0;
    @track wizardState = {
        templateId:     null,
        templateTokens: [],
        primaryObject:  null,
        relatedObjects: [],
        tokenMappings:  [],
        variables:      []
    };

    stepLabels = STEP_LABELS;

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
        if (this.currentStep < STEP_LABELS.length - 1) {
            this.currentStep++;
        }
    }

    handleBack() {
        if (this.currentStep > 0) this.currentStep--;
    }
}
