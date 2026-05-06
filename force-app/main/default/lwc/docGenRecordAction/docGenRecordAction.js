import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, getFieldValue }           from 'lightning/uiRecordApi';
import { ShowToastEvent }                     from 'lightning/platformShowToastEvent';
import getTemplatesForObject  from '@salesforce/apex/DocGen_Controller.getTemplatesForObject';
import getTemplateConfig      from '@salesforce/apex/DocGen_Controller.getTemplateConfig';
import generatePreview        from '@salesforce/apex/DocGen_Controller.generatePreview';
import storePreviewHtml       from '@salesforce/apex/DocGen_Controller.storePreviewHtml';
import generateDocument       from '@salesforce/apex/DocGen_Controller.generateDocument';
import storeMergedHtml        from '@salesforce/apex/DocGen_Controller.storeMergedHtml';

export default class DocGenRecordAction extends LightningElement {
    @api recordId;       // auto-injected by Lightning record page
    @api objectApiName;  // auto-injected by Lightning record page

    @track _nameFields = [];
    @track recordName  = '';

    // Modal
    @track isModalOpen = false;

    // Template search / selection
    @track templates        = [];
    @track templateSearch   = '';
    @track showDropdown     = false;
    @track selectedTemplate = null;  // { Id, Name }
    @track loadedConfig     = null;  // TemplateLoadResultWrapper
    @track isLoadingConfig  = false;

    // UI state
    @track isLoading         = false;
    @track isGenerating      = false;
    @track generatingMessage = 'Generating document…';
    @track error             = null;
    @track successMessage    = null;
    @track lastGeneratedDocId = null;

    // ── Wire: fetch record Name dynamically ─────────────────────────────────
    @wire(getRecord, { recordId: '$recordId', fields: '$_nameFields' })
    _wiredRecord({ data }) {
        if (data && this._nameFields.length) {
            this.recordName = getFieldValue(data, this._nameFields[0]) || '';
        }
    }

    connectedCallback() {
        if (this.objectApiName) {
            this._nameFields = [`${this.objectApiName}.Name`];
        }
    }

    // ── Computed getters ─────────────────────────────────────────────────────

    get filteredTemplates() {
        if (!this.templateSearch) return this.templates;
        const t = this.templateSearch.toLowerCase();
        return this.templates.filter(tmpl => tmpl.Name.toLowerCase().includes(t));
    }

    get hasFilteredTemplates() { return this.filteredTemplates.length > 0; }
    get hasSelectedTemplate()  { return !!this.selectedTemplate; }
    get showActions()          { return !!(this.selectedTemplate && this.loadedConfig); }
    get isActionDisabled()     { return this.isGenerating || !this.showActions; }
    get lastGeneratedFileUrl() {
        return this.lastGeneratedDocId
            ? `/lightning/r/ContentDocument/${this.lastGeneratedDocId}/view`
            : '#';
    }

    // ── Modal open/close ─────────────────────────────────────────────────────

    async handleOpenModal() {
        this.isModalOpen = true;
        this._reset();
        await this._loadTemplates();
    }

    handleClose() {
        if (this.isGenerating) return;
        this.isModalOpen = false;
    }

    // ── Template loading ─────────────────────────────────────────────────────

    async _loadTemplates() {
        if (this.templates.length) {
            this.showDropdown = true;
            return;
        }
        this.isLoading = true;
        this.error = null;
        try {
            this.templates = await getTemplatesForObject({ objectName: this.objectApiName || '' });
            this.showDropdown = true;
        } catch (e) {
            this.error = this._msg(e);
        } finally {
            this.isLoading = false;
        }
    }

    handleTemplateSearch(evt) {
        this.templateSearch = evt.target.value;
        this.showDropdown   = true;
    }

    handleSearchFocus() {
        this.showDropdown = true;
    }

    handleSearchBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showDropdown = false; }, 150);
    }

    handleSearchKeydown(evt) {
        if (evt.key === 'Escape') this.showDropdown = false;
    }

    async handleSelectTemplate(evt) {
        const id   = evt.currentTarget.dataset.id;
        const name = evt.currentTarget.dataset.name;
        this.selectedTemplate = { Id: id, Name: name };
        this.templateSearch   = '';
        this.showDropdown     = false;
        this.loadedConfig     = null;
        this.error            = null;
        this.successMessage   = null;

        this.isLoadingConfig = true;
        try {
            this.loadedConfig = await getTemplateConfig({ templateRecordId: id });
        } catch (e) {
            this.error = this._msg(e);
            this.selectedTemplate = null;
        } finally {
            this.isLoadingConfig = false;
        }
    }

    handleClearTemplate() {
        this.selectedTemplate = null;
        this.loadedConfig     = null;
        this.templateSearch   = '';
        this.error            = null;
        this.successMessage   = null;
        this.showDropdown     = true;
    }

    // ── Action: Open Template (generate preview → new tab) ────────────────────

    async handleOpenTemplate() {
        if (!this.loadedConfig) return;
        this.error          = null;
        this.successMessage = null;
        this.isGenerating   = true;
        this.generatingMessage = 'Generating preview…';
        try {
            const configJson = this._configJson();
            const html  = await generatePreview({ configJson });
            const cvId  = await storePreviewHtml({ htmlContent: html });
            window.open(`/apex/DocGen_HtmlViewer?cvId=${cvId}`, '_blank');
        } catch (e) {
            this.error = this._msg(e);
        } finally {
            this.isGenerating = false;
        }
    }

    // ── Action: Download as PDF ───────────────────────────────────────────────

    async handleDownloadPdf() {
        if (!this.loadedConfig) return;
        this.error          = null;
        this.successMessage = null;
        this.isGenerating   = true;
        this.generatingMessage = 'Preparing document…';
        try {
            const tempCvId = await storeMergedHtml({ configJson: this._configJson() });
            this.generatingMessage = 'Generating PDF…';
            const result = await generateDocument({
                configJson:     this._configJson(),
                format:         'PDF',
                linkedRecordId: this.recordId,
                tempCvId:       tempCvId
            });
            if (result.success) {
                this.lastGeneratedDocId = result.contentDocumentId;
                this._download(result.base64Content, result.fileName, 'application/pdf');
                this.successMessage = `${result.fileName} saved to Salesforce Files.`;
                this._toast('success', `PDF generated — ${result.fileName}`);
            } else {
                this.error = result.errorMessage || 'Document generation failed.';
            }
        } catch (e) {
            this.error = this._msg(e);
        } finally {
            this.isGenerating = false;
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    _configJson() {
        return JSON.stringify({
            templateId              : this.loadedConfig.templateId,
            templateName            : this.loadedConfig.templateName,
            existingTemplateRecordId: this.loadedConfig.templateRecordId,
            primaryObject           : this.loadedConfig.primaryObject,
            recordId                : this.recordId,
            tokenMappings           : this.loadedConfig.tokenMappings || [],
            variables               : this.loadedConfig.variables     || []
        });
    }

    _download(base64, fileName, mimeType) {
        const bytes = atob(base64);
        const arr   = new Uint8Array(bytes.length);
        for (let i = 0; i < bytes.length; i++) arr[i] = bytes.charCodeAt(i);
        const blob = new Blob([arr], { type: mimeType });
        const url  = URL.createObjectURL(blob);
        const a    = document.createElement('a');
        a.href     = url;
        a.download = fileName;
        a.click();
        URL.revokeObjectURL(url);
    }

    _toast(variant, message, title = '') {
        this.dispatchEvent(new ShowToastEvent({
            title  : title || (variant === 'success' ? 'Success' : 'Error'),
            message,
            variant
        }));
    }

    _msg(err) {
        if (typeof err === 'string') return err;
        if (err?.body?.message)      return err.body.message;
        if (err?.message)            return err.message;
        return 'An unexpected error occurred.';
    }

    _reset() {
        this.selectedTemplate   = null;
        this.loadedConfig       = null;
        this.templateSearch     = '';
        this.showDropdown       = false;
        this.error              = null;
        this.successMessage     = null;
        this.lastGeneratedDocId = null;
    }
}
