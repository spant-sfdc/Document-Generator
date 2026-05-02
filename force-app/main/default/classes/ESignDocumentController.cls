/**
 * Controller for the public SignDocument Visualforce page.
 *
 * Security model:
 *  - `without sharing` — token is the sole access key; sharing rules don't apply.
 *  - This controller performs NO DML. All state changes (Viewed, Signed, Declined)
 *    are delegated to ESignSigningQueueable, which runs in system context and
 *    holds the AllowsCallouts interface for the PDF stamp service.
 *  - Signature data (base64) is passed to the Queueable; it is never persisted
 *    directly from this class.
 *  - Rate limiting is enforced via a cache-backed counter per token.
 */
public without sharing class ESignDocumentController {

    // ─────────────────────────────────────────────────────────────────────────
    // VIEW STATE
    // ─────────────────────────────────────────────────────────────────────────

    public Signature_Request__c signRequest  { get; private set; }
    public String  errorCode                 { get; private set; }
    public String  documentBase64            { get; private set; }
    public String  pageState                 { get; private set; } // LOADING | SIGNING | COMPLETE | ERROR
    public Boolean isSubmitting              { get; set; }

    // Signer-supplied inputs (set by VF page via apex:inputHidden)
    public String signatureData       { get; set; } // base64 data-URI from canvas/upload
    public String signatureType       { get; set; } // Draw | Type | Upload
    public String declineReason       { get; set; }
    public String declineDescription  { get; set; }

    private String token;

    // ─────────────────────────────────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────────────────────────────────

    public ESignDocumentController() {
        token        = ApexPages.currentPage().getParameters().get('token');
        isSubmitting = false;
        pageState    = 'LOADING';
        System.debug(LoggingLevel.ERROR, '[CP-1] Controller constructed. token blank=' + String.isBlank(token));
        initialise();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INITIALISE (token validation + document load)
    // ─────────────────────────────────────────────────────────────────────────

    private void initialise() {
        try {
            if (String.isBlank(token)) {
                System.debug(LoggingLevel.ERROR, '[CP-2] FAIL: token is blank');
                errorCode = 'TOKEN_INVALID';
                pageState = 'ERROR';
                return;
            }
            System.debug(LoggingLevel.ERROR, '[CP-2] Token received: ' + ESignTokenService.maskToken(token));

            checkRateLimit();
            System.debug(LoggingLevel.ERROR, '[CP-3] Rate limit passed');

            signRequest = ESignTokenService.validateAndFetch(token);
            System.debug(LoggingLevel.ERROR,
                '[CP-4] Request fetched. Id=' + signRequest.Id
                + ' Status=' + signRequest.Status__c
                + ' ContentVersionId=' + signRequest.Content_Version_Id__c);

            try {
                if (String.isNotBlank(signRequest.Content_Version_Id__c)) {
                    documentBase64 = ESignDocumentService.getVersionBase64(
                        signRequest.Content_Version_Id__c);
                }
                System.debug(LoggingLevel.ERROR,
                    '[CP-5] documentBase64 length=' + (documentBase64 != null ? documentBase64.length() : 0));
            } catch (Exception docEx) {
                System.debug(LoggingLevel.ERROR,
                    '[CP-5] FAIL document preview: ' + docEx.getMessage());
            }

            try {
                if (signRequest.Status__c == 'Pending' || signRequest.Status__c == 'Viewed') {
                    System.enqueueJob(new ESignSigningQueueable(
                        ESignSigningQueueable.ACTION_VIEWED,
                        token, getClientIP(), getUserAgent()
                    ));
                    System.debug(LoggingLevel.ERROR, '[CP-6] Viewed queueable enqueued');
                }
            } catch (Exception qEx) {
                System.debug(LoggingLevel.ERROR, '[CP-6] FAIL Viewed enqueue: ' + qEx.getMessage());
            }

            pageState = 'SIGNING';
            System.debug(LoggingLevel.ERROR, '[CP-7] pageState=SIGNING');

        } catch (ESignException e) {
            System.debug(LoggingLevel.ERROR, '[CP-ERR] ESignException: ' + e.getMessage());
            String code = e.getMessage();
            if (code == 'TOKEN_MISSING' || String.isBlank(code)) { code = 'TOKEN_INVALID'; }
            else if (code.startsWith('DOCUMENT_ERROR')) { code = 'UNEXPECTED_ERROR'; }
            errorCode = code;
            pageState = 'ERROR';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[CP-ERR] Unexpected: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            errorCode = 'UNEXPECTED_ERROR';
            pageState = 'ERROR';
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SUBMIT SIGNATURE
    // ─────────────────────────────────────────────────────────────────────────

    public PageReference submitSignature() {
        System.debug(LoggingLevel.ERROR, '[CP-8] submitSignature called. isSubmitting=' + isSubmitting);
        if (isSubmitting) return null;
        isSubmitting = true;

        try {
            signRequest = ESignTokenService.validateAndFetch(token);
            System.debug(LoggingLevel.ERROR,
                '[CP-9] Re-validated. sigDataBlank=' + String.isBlank(signatureData)
                + ' sigType=' + signatureType
                + ' sigDataLen=' + (signatureData != null ? signatureData.length() : 0));

            if (String.isBlank(signatureData) || String.isBlank(signatureType)) {
                ApexPages.addMessage(new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'Please provide a signature before submitting.'));
                isSubmitting = false;
                return null;
            }

            System.enqueueJob(new ESignSigningQueueable(
                token, signatureData, signatureType,
                getClientIP(), getUserAgent()
            ));
            System.debug(LoggingLevel.ERROR, '[CP-10] Sign queueable enqueued');

            signRequest.Status__c = 'Signed';
            pageState = 'COMPLETE';
            System.debug(LoggingLevel.ERROR, '[CP-11] submitSignature complete. pageState=COMPLETE');

        } catch (ESignException e) {
            System.debug(LoggingLevel.ERROR, '[CP-ERR] submitSignature ESignException: ' + e.getMessage());
            errorCode    = e.getMessage();
            pageState    = 'ERROR';
            isSubmitting = false;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[CP-ERR] submitSignature Exception: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            errorCode    = 'UNEXPECTED_ERROR';
            pageState    = 'ERROR';
            isSubmitting = false;
        }
        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DECLINE
    // ─────────────────────────────────────────────────────────────────────────

    public PageReference declineSignature() {
        System.debug(LoggingLevel.ERROR,
            '[CP-8D] declineSignature called. reason=' + declineReason
            + ' descBlank=' + String.isBlank(declineDescription));
        try {
            signRequest = ESignTokenService.validateAndFetch(token);
            System.debug(LoggingLevel.ERROR, '[CP-9D] Re-validated for decline');

            System.enqueueJob(new ESignSigningQueueable(
                ESignSigningQueueable.ACTION_DECLINE,
                token, declineReason, declineDescription,
                getClientIP(), getUserAgent()
            ));
            System.debug(LoggingLevel.ERROR, '[CP-10D] Decline queueable enqueued');

            signRequest.Status__c = 'Declined';
            pageState = 'COMPLETE';
            System.debug(LoggingLevel.ERROR, '[CP-11D] declineSignature complete');

        } catch (ESignException e) {
            System.debug(LoggingLevel.ERROR, '[CP-ERR] declineSignature ESignException: ' + e.getMessage());
            errorCode = e.getMessage();
            pageState = 'ERROR';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[CP-ERR] declineSignature Exception: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            errorCode = 'UNEXPECTED_ERROR';
            pageState = 'ERROR';
        }
        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RATE LIMITING
    // ─────────────────────────────────────────────────────────────────────────

    private void checkRateLimit() {
        if (String.isBlank(token)) return;

        Integer maxLoads = Integer.valueOf(System.Label.ESign_Rate_Limit_Per_Hour);
        String  cacheKey = 'local.ESign.' + token.substring(0, Math.min(20, token.length()));

        Integer loadCount = 0;
        try {
            Object cached = Cache.Session.get(cacheKey);
            loadCount = (cached != null) ? (Integer) cached : 0;
        } catch (Exception cacheEx) {
            return; // Session cache unavailable — fail open
        }

        if (loadCount >= maxLoads) {
            ESignAuditService.logRateLimit(null, null, token, getClientIP(), loadCount);
            throw new ESignException('RATE_LIMITED');
        }

        try {
            Cache.Session.put(cacheKey, loadCount + 1, 3600);
        } catch (Exception ignored) {}
    }

    // ─────────────────────────────────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    private String getClientIP() {
        return ApexPages.currentPage().getHeaders().get('X-Salesforce-SIP');
    }

    private String getUserAgent() {
        String ua = ApexPages.currentPage().getHeaders().get('USER-AGENT');
        return (ua != null && ua.length() > 255) ? ua.substring(0, 255) : ua;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CONVENIENCE BOOLEANS for VF rendered="" bindings
    // ─────────────────────────────────────────────────────────────────────────

    public Boolean isErrorState    { get { return pageState == 'ERROR'; } }
    public Boolean isSigningState  { get { return pageState == 'SIGNING'; } }
    public Boolean isCompleteState { get { return pageState == 'COMPLETE'; } }

    public Boolean isTokenInvalid   { get { return errorCode == 'TOKEN_INVALID'; } }
    public Boolean isTokenExpired   { get { return errorCode == 'TOKEN_EXPIRED'; } }
    public Boolean isAlreadySigned  { get { return errorCode == 'ALREADY_SIGNED'; } }
    public Boolean isDeclined       { get { return errorCode == 'REQUEST_DECLINED'; } }
    public Boolean isCancelled      { get { return errorCode == 'REQUEST_CANCELLED'; } }
    public Boolean isRateLimited    { get { return errorCode == 'RATE_LIMITED'; } }
    public Boolean isUnexpected     { get { return errorCode == 'UNEXPECTED_ERROR'; } }

    public Boolean isSignedComplete {
        get { return isCompleteState && signRequest?.Status__c == 'Signed'; }
    }
    public Boolean isDeclinedComplete {
        get { return isCompleteState && signRequest?.Status__c == 'Declined'; }
    }
}
