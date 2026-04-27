import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generatePreview    from '@salesforce/apex/DocGen_Controller.generatePreview';
import generateDocument   from '@salesforce/apex/DocGen_Controller.generateDocument';
import saveTemplateConfig from '@salesforce/apex/DocGen_Controller.saveTemplateConfig';

export default class DocGenPreviewDownload extends NavigationMixin(LightningElement) {
    @api templateConfig = null;

    @track recordId          = '';
    @track previewHtml       = null;
    @track isLoading         = false;
    @track isGenerating      = false;
    @track savedFileId       = null;
    @track savedTemplateId   = null;
    @track savedTemplateName = null;
    @track error             = null;

    get hasPreview()       { return !!this.previewHtml; }
    get hasSavedTemplate() { return !!this.savedTemplateId; }
    get fileUrl()          { return this.savedFileId ? `/lightning/r/ContentDocument/${this.savedFileId}/view` : '#'; }

    handleRecordIdChange(evt) {
        this.recordId = evt.target.value;
    }

    async handleGeneratePreview() {
        this.isLoading   = true;
        this.error       = null;
        this.previewHtml = null;
        try {
            const config = { ...this.templateConfig, recordId: this.recordId };
            this.previewHtml = await generatePreview({ configJson: JSON.stringify(config) });
        } catch (e) {
            this.error = e;
        } finally {
            this.isLoading = false;
        }
    }

    async handleDownloadPdf() {
        await this._downloadDocument('PDF', 'application/pdf');
    }

    async handleDownloadWord() {
        await this._downloadDocument('WORD', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    }

    async _downloadDocument(format, mimeType) {
        this.isGenerating = true;
        this.error        = null;
        try {
            const config   = { ...this.templateConfig, recordId: this.recordId };
            const response = await generateDocument({
                configJson:     JSON.stringify(config),
                format,
                linkedRecordId: this.recordId || null
            });
            if (response.success && response.base64Content) {
                this.savedFileId = response.contentDocumentId;
                this._triggerBrowserDownload(response.base64Content, response.fileName, mimeType);
            } else {
                this.error = response.errorMessage || 'Document generation failed.';
            }
        } catch (e) {
            this.error = e;
        } finally {
            this.isGenerating = false;
        }
    }

    _triggerBrowserDownload(base64, fileName, mimeType) {
        const bytes = atob(base64);
        const arr   = new Uint8Array(bytes.length);
        for (let i = 0; i < bytes.length; i++) arr[i] = bytes.charCodeAt(i);
        const blob  = new Blob([arr], { type: mimeType });
        const url   = URL.createObjectURL(blob);
        const a     = document.createElement('a');
        a.href      = url;
        a.download  = fileName;
        a.click();
        URL.revokeObjectURL(url);
    }

    async handleSaveToFiles() {
        if (!this.recordId) {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Record ID Required',
                message: 'Enter a Record ID to attach the file to a Salesforce record.',
                variant: 'warning'
            }));
            return;
        }
        await this._downloadDocument('PDF', 'application/pdf');
    }

    async handleSaveConfig() {
        this.error = null;
        try {
            const result = await saveTemplateConfig({
                configJson: JSON.stringify(this.templateConfig)
            });
            this.savedTemplateId   = result.templateId;
            this.savedTemplateName = result.templateName;
            this.dispatchEvent(new ShowToastEvent({
                title:   'Template Saved',
                message: `Template ${result.templateName} created successfully.`,
                variant: 'success',
                mode:    'sticky'
            }));
        } catch (e) {
            this.error = e;
        }
    }

    handleViewTemplate() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId:   this.savedTemplateId,
                actionName: 'view'
            }
        });
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('stepback', { bubbles: true, composed: true }));
    }
}
