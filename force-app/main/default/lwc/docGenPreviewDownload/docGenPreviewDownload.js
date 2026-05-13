import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generatePreview      from '@salesforce/apex/DocGen_Controller.generatePreview';
import storePreviewHtml     from '@salesforce/apex/DocGen_Controller.storePreviewHtml';
import generateDocument     from '@salesforce/apex/DocGen_Controller.generateDocument';
import saveTemplateConfig   from '@salesforce/apex/DocGen_Controller.saveTemplateConfig';
import updateTemplateConfig from '@salesforce/apex/DocGen_Controller.updateTemplateConfig';
import savePdf              from '@salesforce/apex/PdfGenerationController.savePdf';
import {
    initialize       as initPdfEngine,
    htmlToPdf,
    pdfBytesToBase64,
    previewPdf       as createPreviewUrl,
    revokePreviewed
} from 'c/pdfGenerationEngine';

export default class DocGenPreviewDownload extends NavigationMixin(LightningElement) {
    _templateConfig = null;
    @api
    get templateConfig() { return this._templateConfig; }
    set templateConfig(val) {
        this._templateConfig = val;
        if (val && val.templateName && !this.templateName) {
            this.templateName = val.templateName;
        }
    }

    @track recordId          = '';
    @track templateName      = '';
    @track previewHtml       = null;
    @track previewCvId       = null;
    @track isLoading         = false;
    @track isGenerating      = false;
    @track savedFileId       = null;
    @track savedTemplateId   = null;
    @track savedTemplateName = null;
    @track error             = null;

    _pdfPreviewUrl = null;   // object URL for PDF preview iframe

    get isEditMode()       { return !!(this._templateConfig && this._templateConfig.existingTemplateRecordId); }
    get saveButtonLabel()  { return this.isEditMode ? 'Update Template' : 'Save Template Config'; }
    get hasPreview()       { return !!this.previewCvId; }
    get hasSavedTemplate() { return !!this.savedTemplateId; }
    get fileUrl()          { return this.savedFileId ? `/lightning/r/ContentDocument/${this.savedFileId}/view` : '#'; }
    get previewSrc()       { return this.previewCvId ? `/apex/DocGen_HtmlViewer?cvId=${this.previewCvId}` : 'about:blank'; }

    connectedCallback() {
        // Load PDF-LIB + html2canvas eagerly so they are ready when user clicks
        initPdfEngine(this).catch(err => {
            console.warn('[DocGen] PDF engine libraries failed to load:', err);
        });
    }

    disconnectedCallback() {
        revokePreviewed(this._pdfPreviewUrl);
    }

    handleRecordIdChange(evt)    { this.recordId    = evt.target.value; }
    handleTemplateNameChange(evt){ this.templateName = evt.target.value; }

    async handleGeneratePreview() {
        this.isLoading   = true;
        this.error       = null;
        this.previewHtml = null;
        this.previewCvId = null;
        try {
            const config     = { ...this.templateConfig, recordId: this.recordId };
            this.previewHtml = await generatePreview({ configJson: JSON.stringify(config) });
            this.previewCvId = await storePreviewHtml({ htmlContent: this.previewHtml });
        } catch (e) {
            this.error = e;
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Download PDF using PDF-LIB: renders the in-memory previewHtml to a PDF
     * and triggers a browser download. No server-side VF rendering.
     */
    async handleDownloadPdf() {
        if (!this.previewHtml) return;
        this.isGenerating = true;
        this.error        = null;
        try {
            const pdfBytes = await htmlToPdf(this.previewHtml);
            const base64   = pdfBytesToBase64(pdfBytes);
            this._triggerBrowserDownload(
                base64,
                `Document_${_timestamp()}.pdf`,
                'application/pdf'
            );
        } catch (e) {
            this.error = e;
        } finally {
            this.isGenerating = false;
        }
    }

    async handleDownloadWord() {
        await this._downloadDocument('WORD', 'application/msword');
    }

    /**
     * Generate PDF via PDF-LIB, save to Salesforce Files, and link to the record.
     */
    async handleSaveToFiles() {
        if (!this.recordId) {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Record ID Required',
                message: 'Enter a Record ID to attach the file to a Salesforce record.',
                variant: 'warning'
            }));
            return;
        }
        if (!this.previewHtml) {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Generate Preview First',
                message: 'Click "Generate Preview" before saving.',
                variant: 'warning'
            }));
            return;
        }
        this.isGenerating = true;
        this.error        = null;
        try {
            const pdfBytes  = await htmlToPdf(this.previewHtml);
            const base64    = pdfBytesToBase64(pdfBytes);
            const fileName  = `Document_${_timestamp()}`;
            const docId     = await savePdf({
                base64Pdf: base64,
                fileName,
                parentId: this.recordId
            });
            this.savedFileId = docId;
            this.dispatchEvent(new ShowToastEvent({
                title:   'PDF Saved',
                message: 'Document saved to Files.',
                variant: 'success'
            }));
        } catch (e) {
            this.error = e;
        } finally {
            this.isGenerating = false;
        }
    }

    // ── Word download still goes through the existing Apex route ─────────────

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

    async handleSaveConfig() {
        this.error = null;
        try {
            const config = { ...this.templateConfig, templateName: this.templateName };
            let result;
            if (this.isEditMode) {
                result = await updateTemplateConfig({
                    templateRecordId: config.existingTemplateRecordId,
                    configJson:       JSON.stringify(config)
                });
            } else {
                result = await saveTemplateConfig({ configJson: JSON.stringify(config) });
            }
            this.savedTemplateId   = result.templateId;
            this.savedTemplateName = result.templateName;
            this.dispatchEvent(new ShowToastEvent({
                title:   this.isEditMode ? 'Template Updated' : 'Template Saved',
                message: `"${result.templateName}" ${this.isEditMode ? 'updated' : 'created'} successfully.`,
                variant: 'success',
                mode:    'sticky'
            }));
        } catch (e) {
            this.error = e;
        }
    }

    handleViewTemplate() {
        this[NavigationMixin.Navigate]({
            type:       'standard__recordPage',
            attributes: { recordId: this.savedTemplateId, actionName: 'view' }
        });
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('stepback', { bubbles: true, composed: true }));
    }
}

function _timestamp() {
    return new Date().toISOString().replace(/[-:T]/g, '').substring(0, 15);
}
