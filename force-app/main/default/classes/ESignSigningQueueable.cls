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
        System.debug(LoggingLevel.DEBUG,
            'ESignSigningQueueable.execute action=' + action
            + ' token=' + ESignTokenService.maskToken(token));
        try {
            if (action == ACTION_VIEWED) {
                processViewed();
            } else if (action == ACTION_DECLINE) {
                processDecline();
            } else {
                processSign();
            }
        } catch (ESignException e) {
            System.debug(LoggingLevel.ERROR,
                'ESignSigningQueueable ESignException action=' + action + ': ' + e.getMessage());
            tryLogError(e.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'ESignSigningQueueable Exception action=' + action + ': ' + e.getMessage()
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
        Signature_Request__c req = ESignTokenService.validateAndFetch(token);

        // Duplicate-sign guard — token validation ensures Pending/Viewed only
        // but a race between two simultaneous submits needs a hard check here
        if (req.Status__c != 'Pending' && req.Status__c != 'Viewed') return;

        Blob sigBlob = decodeBlob(signatureData);

        // Save signature image and link it to the request record
        String sigImageDocId = ESignDocumentService.saveSignatureImage(
            req.Name, sigBlob);
        ESignDocumentService.linkDocumentToRecord(sigImageDocId, req.Id);

        // Update request → Signed (first write)
        req.Status__c             = 'Signed';
        req.Signed_DateTime__c    = DateTime.now();
        req.Signer_Email__c       = req.Recipient_Email__c;
        req.Signature_Type__c     = signatureType;
        req.Signing_IP__c         = clientIP;
        req.Signer_User_Agent__c  = userAgent;
        req.Signature_Image_Id__c = sigImageDocId;
        Database.update(req, AccessLevel.SYSTEM_MODE);

        // Create signed document version (Tier 1 always; Tier 2 callout if configured)
        String signedDocId = ESignDocumentService.createSignedVersion(req, sigBlob);

        // Store signed document id on request (second write)
        req.Signed_Document_Id__c = signedDocId;
        Database.update(req, AccessLevel.SYSTEM_MODE);

        ESignAuditService.log(
            req.Id, 'Signed',
            req.Signer_Email__c, token,
            clientIP, userAgent, 'SiteAsync'
        );
    }

    // ── Decline ─────────────────────────────────────────────────────────────

    private void processDecline() {
        Signature_Request__c req = ESignTokenService.validateAndFetch(token);
        if (req.Status__c != 'Pending' && req.Status__c != 'Viewed') return;

        req.Status__c = 'Declined';
        if (String.isNotBlank(declineReason))      req.Decline_Reason__c      = declineReason;
        if (String.isNotBlank(declineDescription)) req.Decline_Description__c = declineDescription;
        Database.update(req, AccessLevel.SYSTEM_MODE);

        ESignAuditService.log(
            req.Id, 'Declined',
            req.Recipient_Email__c, token,
            clientIP, userAgent, 'SiteAsync'
        );
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
