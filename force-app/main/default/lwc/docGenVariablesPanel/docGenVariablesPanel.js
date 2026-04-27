import { LightningElement } from 'lwc';

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

export default class DocGenVariablesPanel extends LightningElement {
    systemVariables = SYSTEM_VARIABLES;

    handleBack() {
        this.dispatchEvent(new CustomEvent('stepback', { bubbles: true, composed: true }));
    }

    handleNext() {
        this.dispatchEvent(new CustomEvent('stepcomplete', {
            bubbles: true,
            composed: true,
            detail: { variables: [] }
        }));
    }
}
