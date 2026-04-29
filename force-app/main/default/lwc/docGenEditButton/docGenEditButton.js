import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTemplateConfig from '@salesforce/apex/DocGen_Controller.getTemplateConfig';

// Must match the constant in docGenWizard.js
const EDIT_KEY     = 'docgen_edit_state';
// Developer name of the DocGen Wizard Lightning tab (AppPage — navType-agnostic).
// Navigating to /lightning/n/{tab} works from any Lightning app context, Console or Standard.
const DOCGEN_TAB   = 'DocGen_Wizard';

export default class DocGenEditButton extends NavigationMixin(LightningElement) {
    @api recordId;          // Document_Template__c Id — provided by the record page
    @track isLoading = false;
    @track error     = null;

    async handleEdit() {
        this.isLoading = true;
        this.error     = null;
        try {
            const config = await getTemplateConfig({ templateRecordId: this.recordId });

            const editState = {
                existingTemplateRecordId: config.templateRecordId,
                templateId:               config.templateId,
                templateName:             config.templateName,
                templateTokens:           config.templateTokens  || [],
                sysTokens:                config.sysTokens       || [],
                primaryObject:            config.primaryObject,
                primaryObjectLabel:       config.primaryObject,
                parentObjects:            config.parentObjects   || [],
                childObjects:             config.childObjects    || [],
                relatedObjects:           (config.parentObjects || []).concat(config.childObjects || []).map(o => o.apiName),
                relatedObjectsWithLabels: (config.parentObjects || []).concat(config.childObjects || []),
                tokenMappings:            config.tokenMappings   || [],
                variables:                config.variables       || []
            };

            // Bridge state to the wizard via sessionStorage.
            // Works because DocGen_Document_Generator is a Standard nav app on the same origin.
            try {
                sessionStorage.setItem(EDIT_KEY, JSON.stringify(editState));
            } catch (storageErr) {
                this.error = 'Browser storage is unavailable. Please allow site storage and try again.';
                return;
            }

            // Navigate to the DocGen Wizard Lightning tab.
            // /lightning/n/{tabName} is navType-agnostic — works from Console and Standard apps.
            // The wizard's connectedCallback reads EDIT_KEY and enters edit mode.
            this[NavigationMixin.Navigate]({
                type:       'standard__webPage',
                attributes: { url: `/lightning/n/${DOCGEN_TAB}` }
            });
        } catch (e) {
            this.error = e.body ? e.body.message : (e.message || 'Failed to load template configuration.');
        } finally {
            this.isLoading = false;
        }
    }
}
