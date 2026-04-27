import { LightningElement, api } from 'lwc';

export default class DocGenProgressBar extends LightningElement {
    @api steps = [];
    @api currentStep = 0;

    get stepsWithState() {
        return this.steps.map((label, idx) => ({
            label,
            isCompleted: idx < this.currentStep,
            isCurrent: idx === this.currentStep,
            cssClass: [
                'slds-progress__item',
                idx < this.currentStep ? 'slds-is-completed' : '',
                idx === this.currentStep ? 'slds-is-active' : ''
            ].join(' ').trim(),
            labelCssClass: idx === this.currentStep
                ? 'step-label step-label_active'
                : 'step-label'
        }));
    }

    get progressPercent() {
        if (!this.steps || this.steps.length <= 1) return 0;
        return Math.round((this.currentStep / (this.steps.length - 1)) * 100);
    }

    get progressBarStyle() {
        return `width: ${this.progressPercent}%;`;
    }
}
