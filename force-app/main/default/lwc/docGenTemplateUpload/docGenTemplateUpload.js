import { LightningElement, track } from 'lwc';
import uploadTemplate  from '@salesforce/apex/DocGen_Controller.uploadTemplate';
import extractTokens   from '@salesforce/apex/DocGen_Controller.extractTokens';

export default class DocGenTemplateUpload extends LightningElement {
    @track tokens         = [];
    @track uploadedVersionId = null;
    @track uploadedFileName  = null;
    @track isLoading      = false;
    @track error          = null;

    get tokenCount()     { return this.tokens.length; }
    get isNextDisabled() { return !this.uploadedVersionId || this.isLoading; }

    async handleFileSelected(evt) {
        const file = evt.target.files[0];
        if (!file) return;
        this.isLoading = true;
        this.error     = null;
        this.tokens    = [];
        this.uploadedFileName = file.name;

        try {
            const base64 = await this.readAsBase64(file);
            const cvId   = await uploadTemplate({ base64Content: base64, fileName: file.name });
            this.uploadedVersionId = cvId;
            this.tokens = await extractTokens({ contentVersionId: cvId });
        } catch (e) {
            this.error = e;
            this.uploadedVersionId = null;
        } finally {
            this.isLoading = false;
        }
    }

    readAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload  = () => resolve(reader.result.split(',')[1]);
            reader.onerror = reject;
            reader.readAsDataURL(file);
        });
    }

    handleNext() {
        this.dispatchEvent(new CustomEvent('stepcomplete', {
            bubbles: true,
            composed: true,
            detail: {
                templateId:     this.uploadedVersionId,
                templateTokens: this.tokens
            }
        }));
    }
}
