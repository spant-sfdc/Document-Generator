import { LightningElement, api } from 'lwc';

export default class DocGenErrorPanel extends LightningElement {
    @api errors = null;

    get hasError() {
        return this.message != null;
    }

    get message() {
        if (!this.errors) return null;
        if (typeof this.errors === 'string') return this.errors;
        if (this.errors.body?.message) return this.errors.body.message;
        if (this.errors.message) return this.errors.message;
        if (Array.isArray(this.errors) && this.errors.length > 0) {
            return this.errors[0].message || JSON.stringify(this.errors[0]);
        }
        return JSON.stringify(this.errors);
    }
}
