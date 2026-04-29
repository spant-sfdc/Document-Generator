import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplatesForObject from '@salesforce/apex/DocGen_Controller.getTemplatesForObject';
import getTemplateConfig     from '@salesforce/apex/DocGen_Controller.getTemplateConfig';
import generatePreview       from '@salesforce/apex/DocGen_Controller.generatePreview';
import storePreviewHtml      from '@salesforce/apex/DocGen_Controller.storePreviewHtml';
import generateDocument      from '@salesforce/apex/DocGen_Controller.generateDocument';

export default class DocGenRecordAction extends LightningElement {
    @api recordId;          // Provided automatically by Lightning record page
    @api objectApiName;     // Provided automatically by Lightning record page

    @track isModalOpen       = false;
    @track view              = 'select'; // 'select' | 'preview'
    @track templates         = [];
    @track selectedConfig    = null;
    @track previewCvId       = null;
    @track isLoading         = false;
    @track isGenerating      = false;
    @track savedFileId       = null;
    @track error             = null;

    get hasTemplates()  { return this.templates.length > 0; }
    get isSelectView()  { return this.view === 'select'; }
    get isPreviewView() { return this.view === 'preview'; }
    get hasPreview()    { return !!this.previewCvId; }
    get previewSrc()    { return this.previewCvId ? `/apex/DocGen_HtmlViewer?cvId=${this.previewCvId}` : 'about:blank'; }
    get fileUrl()       { return this.savedFileId ? `/lightning/r/ContentDocument/${this.savedFileId}/view` : '#'; }
    get selectedTemplateName() { return this.selectedConfig ? this.selectedConfig.templateName : ''; }

    async handleOpenModal() {
        this.isModalOpen  = true;
        this.view         = 'select';
        this.templates    = [];
        this.selectedConfig = null;
        this.previewCvId  = null;
        this.savedFileId  = null;
        this.error        = null;
        await this._loadTemplates();
    }

    handleClose() {
        this.isModalOpen = false;
    }

    async _loadTemplates() {
        this.isLoading = true;
        try {
            this.templates = await getTemplatesForObject({ objectName: this.objectApiName || '' });
        } catch (e) {
            this.error = e.body ? e.body.message : (e.message || 'Failed to load templates.');
        } finally {
            this.isLoading = false;
        }
    }

    async handleSelectTemplate(evt) {
        const tmplId = evt.currentTarget.dataset.id;
        this.isLoading    = true;
        this.error        = null;
        this.previewCvId  = null;
        this.savedFileId  = null;
        try {
            // Load full config (mappings + variables) for this template
            const config = await getTemplateConfig({ templateRecordId: tmplId });
            this.selectedConfig = config;

            // Generate merged preview immediately
            const mergeConfig = {
                templateId:    config.templateId,
                primaryObject: config.primaryObject,
                tokenMappings: config.tokenMappings,
                variables:     config.variables,
                recordId:      this.recordId
            };
            const html       = await generatePreview({ configJson: JSON.stringify(mergeConfig) });
            this.previewCvId = await storePreviewHtml({ htmlContent: html });
            this.view        = 'preview';
        } catch (e) {
            this.error = e.body ? e.body.message : (e.message || 'Failed to generate preview.');
        } finally {
            this.isLoading = false;
        }
    }

    handleOpenPdf() {
        if (this.previewCvId) {
            window.open(`/apex/DocGen_HtmlViewer?cvId=${this.previewCvId}`, '_blank');
        }
    }

    async handleDownloadWord() {
        await this._generateAndDownload('WORD', 'application/msword');
    }

    async handleSaveToFiles() {
        await this._generateAndDownload('PDF', 'application/pdf');
    }

    async _generateAndDownload(format, mimeType) {
        this.isGenerating = true;
        this.error        = null;
        try {
            const config = {
                templateId:    this.selectedConfig.templateId,
                primaryObject: this.selectedConfig.primaryObject,
                tokenMappings: this.selectedConfig.tokenMappings,
                variables:     this.selectedConfig.variables,
                recordId:      this.recordId
            };
            const response = await generateDocument({
                configJson:     JSON.stringify(config),
                format,
                linkedRecordId: this.recordId
            });
            if (response.success && response.base64Content) {
                this.savedFileId = response.contentDocumentId;
                this._triggerBrowserDownload(response.base64Content, response.fileName, mimeType);
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Document Generated',
                    message: `${response.fileName} saved to Salesforce Files.`,
                    variant: 'success'
                }));
            } else {
                this.error = response.errorMessage || 'Document generation failed.';
            }
        } catch (e) {
            this.error = e.body ? e.body.message : (e.message || 'Document generation failed.');
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

    handleBackToTemplates() {
        this.view        = 'select';
        this.previewCvId = null;
        this.savedFileId = null;
        this.error       = null;
    }
}
