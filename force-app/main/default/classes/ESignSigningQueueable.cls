/**
 * Async worker for the eSign signing flow.
 *
 * Runs outside the guest-user synchronous VF context, which means:
 *  - AccessLevel.SYSTEM_MODE DML is not restricted by Guest User License
 *  - HTTP callouts (PDF stamp service) are allowed alongside DML
 *  - Duplicate-sign is guarded: Queueable checks status before any DML
 */
public without sharing class ESignSigningQueueable
        implements Queueable, Database.AllowsCallouts {

    public  static final String ACTION_SIGN    = 'Sign';
    public  static final String ACTION_DECLINE = 'Decline';
    public  static final String ACTION_VIEWED  = 'Viewed';

    private final String action;
    private final String token;
    private final String signatureData;    // base64 data-URI (null for Decline/Viewed)
    private final String signatureType;
    private final String declineReason;
    private final String declineDescription;
    private final String clientIP;
    private final String userAgent;

    // ── Constructors ────────────────────────────────────────────────────────

    // Sign constructor
    public ESignSigningQueueable(String token,
                                 String signatureData,
                                 String signatureType,
                                 String clientIP,
                                 String userAgent) {
        this.action             = ACTION_SIGN;
        this.token              = token;
        this.signatureData      = signatureData;
        this.signatureType      = signatureType;
        this.declineReason      = null;
        this.declineDescription = null;
        this.clientIP           = clientIP;
        this.userAgent          = userAgent;
    }

    // Viewed constructor
    public ESignSigningQueueable(String action,
                                 String token,
                                 String clientIP,
                                 String userAgent) {
        this.action             = action; // ACTION_VIEWED
        this.token              = token;
        this.signatureData      = null;
        this.signatureType      = null;
        this.declineReason      = null;
        this.declineDescription = null;
        this.clientIP           = clientIP;
        this.userAgent          = userAgent;
    }

    // Decline constructor — carries reason + description
    public ESignSigningQueueable(String action,
                                 String token,
                                 String declineReason,
                                 String declineDescription,
                                 String clientIP,
                                 String userAgent) {
        this.action             = action; // ACTION_DECLINE
        this.token              = token;
        this.signatureData      = null;
        this.signatureType      = null;
        this.declineReason      = declineReason;
        this.declineDescription = declineDescription;
        this.clientIP           = clientIP;
        this.userAgent          = userAgent;
    }

    // ── execute ─────────────────────────────────────────────────────────────

    public void execute(QueueableContext ctx) {
        System.debug(LoggingLevel.ERROR,
            '[CP-Q1] Queueable execute START. action=' + action
            + ' token=' + ESignTokenService.maskToken(token));
        try {
            if (action == ACTION_VIEWED) {
                processViewed();
            } else if (action == ACTION_DECLINE) {
                processDecline();
            } else {
                processSign();
            }
            System.debug(LoggingLevel.ERROR, '[CP-Q2] Queueable execute COMPLETE. action=' + action);
        } catch (ESignException e) {
            System.debug(LoggingLevel.ERROR,
                '[CP-QERR] ESignException action=' + action + ': ' + e.getMessage()
                + ' | ' + e.getStackTraceString());
            tryLogError(e.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[CP-QERR] Exception action=' + action + ': ' + e.getMessage()
                + ' | ' + e.getStackTraceString());
            tryLogError('Queueable failed: ' + e.getMessage());
        }
    }

    private void tryLogError(String detail) {
        try {
            List<Signature_Request__c> reqs = Database.queryWithBinds(
                'SELECT Id, Recipient_Email__c FROM Signature_Request__c WHERE Secure_Token__c = :tok LIMIT 1',
                new Map<String, Object>{ 'tok' => token },
                AccessLevel.SYSTEM_MODE
            );
            String reqId    = reqs.isEmpty() ? null : reqs[0].Id;
            String reqEmail = reqs.isEmpty() ? null : reqs[0].Recipient_Email__c;
            ESignAuditService.logError(reqId, detail, reqEmail, token, 'SiteAsync');
        } catch (Exception ignored) {
            System.debug(LoggingLevel.ERROR,
                'ESignSigningQueueable.tryLogError failed: ' + ignored.getMessage());
        }
    }

    // ── Sign ────────────────────────────────────────────────────────────────

    private void processSign() {
        System.debug(LoggingLevel.ERROR, '[CP-S1] processSign START');
        Signature_Request__c req = ESignTokenService.validateAndFetch(token);
        System.debug(LoggingLevel.ERROR,
            '[CP-S2] Request fetched. Id=' + req.Id + ' Status=' + req.Status__c
            + ' ContentVersionId=' + req.Content_Version_Id__c);

        if (req.Status__c != 'Pending' && req.Status__c != 'Viewed') {
            System.debug(LoggingLevel.ERROR, '[CP-S3] ABORT: status=' + req.Status__c + ' not signable');
            return;
        }

        Blob sigBlob = decodeBlob(signatureData);
        System.debug(LoggingLevel.ERROR, '[CP-S4] sigBlob size=' + sigBlob.size());

        String sigImageDocId = ESignDocumentService.saveSignatureImage(req.Name, sigBlob);
        System.debug(LoggingLevel.ERROR, '[CP-S5] sigImageDocId=' + sigImageDocId);

        ESignDocumentService.linkDocumentToRecord(sigImageDocId, req.Id);
        System.debug(LoggingLevel.ERROR, '[CP-S6] sig image linked to request');

        req.Status__c             = 'Signed';
        req.Signed_DateTime__c    = DateTime.now();
        req.Signer_Email__c       = req.Recipient_Email__c;
        req.Signature_Type__c     = signatureType;
        req.Signing_IP__c         = clientIP;
        req.Signer_User_Agent__c  = userAgent;
        req.Signature_Image_Id__c = sigImageDocId;
        Database.update(req, AccessLevel.SYSTEM_MODE);
        System.debug(LoggingLevel.ERROR, '[CP-S7] Status updated to Signed');

        String signedDocId = ESignDocumentService.createSignedVersion(req, sigBlob);
        System.debug(LoggingLevel.ERROR, '[CP-S8] signedDocId=' + signedDocId);

        req.Signed_Document_Id__c = signedDocId;
        Database.update(req, AccessLevel.SYSTEM_MODE);
        System.debug(LoggingLevel.ERROR, '[CP-S9] Signed_Document_Id__c written');

        ESignAuditService.log(req.Id, 'Signed', req.Signer_Email__c, token, clientIP, userAgent, 'SiteAsync');
        System.debug(LoggingLevel.ERROR, '[CP-S10] Audit log written. processSign DONE');
    }

    // ── Decline ─────────────────────────────────────────────────────────────

    private void processDecline() {
        System.debug(LoggingLevel.ERROR,
            '[CP-D1] processDecline START. reason=' + declineReason
            + ' descBlank=' + String.isBlank(declineDescription));
        Signature_Request__c req = ESignTokenService.validateAndFetch(token);
        System.debug(LoggingLevel.ERROR,
            '[CP-D2] Request fetched. Id=' + req.Id + ' Status=' + req.Status__c);

        if (req.Status__c != 'Pending' && req.Status__c != 'Viewed') {
            System.debug(LoggingLevel.ERROR, '[CP-D3] ABORT: status=' + req.Status__c);
            return;
        }

        req.Status__c = 'Declined';
        if (String.isNotBlank(declineReason))      req.Decline_Reason__c      = declineReason;
        if (String.isNotBlank(declineDescription)) req.Decline_Description__c = declineDescription;
        Database.update(req, AccessLevel.SYSTEM_MODE);
        System.debug(LoggingLevel.ERROR,
            '[CP-D4] DML done. Status=Declined Reason=' + req.Decline_Reason__c);

        ESignAuditService.log(req.Id, 'Declined', req.Recipient_Email__c, token, clientIP, userAgent, 'SiteAsync');
        System.debug(LoggingLevel.ERROR, '[CP-D5] processDecline DONE');
    }

    // ── Viewed ───────────────────────────────────────────────────────────────

    private void processViewed() {
        Signature_Request__c req = ESignTokenService.validateAndFetch(token);
        if (req.Status__c != 'Pending' && req.Status__c != 'Viewed') return;

        String newStatus = (req.Status__c == 'Pending') ? 'Viewed' : req.Status__c;
        req.Status__c        = newStatus;
        req.Last_Accessed__c = DateTime.now();
        Database.update(req, AccessLevel.SYSTEM_MODE);

        if (newStatus == 'Viewed') {
            ESignAuditService.log(
                req.Id, 'Viewed',
                req.Recipient_Email__c, token,
                clientIP, userAgent, 'SiteAsync'
            );
        }
    }

    // ── Helper ───────────────────────────────────────────────────────────────

    private static Blob decodeBlob(String dataUri) {
        String b64 = dataUri.contains(',') ? dataUri.substringAfter(',') : dataUri;
        try {
            return EncodingUtil.base64Decode(b64);
        } catch (Exception e) {
            throw new ESignException('VALIDATION_ERROR:Invalid signature image data');
        }
    }
}
