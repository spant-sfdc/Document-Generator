import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getViewerData    from '@salesforce/apex/ESignDocumentViewerController.getViewerData';
import getVersionBase64 from '@salesforce/apex/ESignDocumentViewerController.getVersionBase64';

const STATUS_BADGE = {
    signed:    'viewer-badge viewer-badge--signed',
    pending:   'viewer-badge viewer-badge--pending',
    viewed:    'viewer-badge viewer-badge--pending',
    declined:  'viewer-badge viewer-badge--declined',
    cancelled: 'viewer-badge viewer-badge--declined',
    expired:   'viewer-badge viewer-badge--expired',
};

export default class ESignDocumentViewer extends NavigationMixin(LightningElement) {
    @api recordId;

    @track data              = null;
    @track selectedVersionId = null;
    @track sigImgFailed      = false;
    @track previewBase64     = null;
    @track previewLoading    = false;

    isLoading = true;
    hasError  = false;

    // ── Wire ─────────────────────────────────────────────────────────────────

    @wire(getViewerData, { recordId: '$recordId' })
    wiredData({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.data            = data;
            this.selectedVersionId = data.previewVersionId || null;
            this._loadPreview();
        } else if (error) {
            console.error('eSignDocumentViewer wire error', error);
            this.hasError = true;
        }
    }

    // ── Computed ──────────────────────────────────────────────────────────────

    get isReady()     { return !this.isLoading && !this.hasError && this.data != null; }
    get isSigned()    { return this.data?.status === 'Signed'; }
    get hasVersions() { return (this.data?.versions?.length ?? 0) > 0; }
    get signerEmail() { return this.data?.signerEmail || this.data?.recipientEmail; }

    get previewSrc() {
        if (!this.previewBase64) return null;
        return 'data:application/pdf;base64,' + this.previewBase64;
    }

    get sigImageUrl() {
        if (this.sigImgFailed || !this.data?.sigImageVersionId) return null;
        return `/sfc/servlet.shepherd/version/download/${this.data.sigImageVersionId}?operationContext=CHATTER`;
    }

    get versionOptions() {
        return (this.data?.versions || []).map(v => ({
            label : `v${v.versionNumber} — ${v.title}${v.isSigned ? ' ✓ Signed' : ''}`,
            value : v.id,
        }));
    }

    get decoratedVersions() {
        return (this.data?.versions || []).map(v => ({
            ...v,
            rowClass: [
                'viewer-version-item',
                v.isSigned ? 'viewer-version-item--signed' : '',
                v.id === this.selectedVersionId ? 'viewer-version-item--active' : '',
            ].filter(Boolean).join(' '),
        }));
    }

    get statusBadgeClass() {
        const key = (this.data?.status || '').toLowerCase();
        return STATUS_BADGE[key] || 'viewer-badge viewer-badge--neutral';
    }

    // ── Handlers ──────────────────────────────────────────────────────────────

    handleVersionChange(evt) {
        this.selectedVersionId = evt.detail.value;
        this._loadPreview();
    }

    handleVersionClick(evt) {
        this.selectedVersionId = evt.currentTarget.dataset.id;
        this._loadPreview();
    }

    handleOpenInTab() {
        if (!this.data?.documentId) return;
        this[NavigationMixin.Navigate]({
            type       : 'standard__namedPage',
            attributes : { pageName: 'filePreview' },
            state      : { selectedRecordId: this.data.documentId },
        });
    }

    handleSigImgError() {
        this.sigImgFailed = true;
    }

    // ── Private ───────────────────────────────────────────────────────────────

    _loadPreview() {
        if (!this.selectedVersionId) {
            this.previewBase64 = null;
            return;
        }
        this.previewLoading = true;
        this.previewBase64  = null;
        getVersionBase64({ versionId: this.selectedVersionId })
            .then(result => {
                this.previewBase64  = result;
                this.previewLoading = false;
            })
            .catch(err => {
                console.error('eSignDocumentViewer: getVersionBase64 failed', err);
                this.previewLoading = false;
            });
    }
}
