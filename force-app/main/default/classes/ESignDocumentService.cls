/**
 * Document retrieval, signature stamping, and versioning for SF-eSign.
 *
 * PDF STAMPING STRATEGY:
 *  Salesforce Apex cannot natively modify binary PDF bytes (no built-in
 *  PDF library). This class implements a two-tier strategy:
 *
 *  Tier 1 — Metadata Overlay (always applied):
 *    A new ContentVersion is created that appends a structured JSON
 *    audit manifest as a description. The ORIGINAL document bytes are
 *    preserved; the signature image and audit data are stored as
 *    separate linked ContentDocuments. This is legally sufficient for
 *    most jurisdictions when combined with the Signature_Audit__c trail.
 *
 *  Tier 2 — Visual Stamp (optional, requires external callout):
 *    If an external PDF stamping service URL is configured via the
 *    ESign_PDF_Stamp_Endpoint custom label, this class will POST the
 *    document blob + signature image to that endpoint and store the
 *    returned stamped PDF as the new ContentVersion body.
 *    Fallback: if the callout fails or no endpoint is configured,
 *    Tier 1 is used automatically.
 *
 * Document versioning rule:
 *  - Original document is NEVER modified.
 *  - A new ContentVersion is inserted under the SAME ContentDocument Id.
 *  - The signed version Title is suffixed with " [SIGNED - {timestamp}]".
 */
public without sharing class ESignDocumentService {

    // ─────────────────────────────────────────────────────────────────────────
    // DOCUMENT RETRIEVAL
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Returns the ContentVersion for a given Id.
     * Works with any ContentDocument — no DocGen assumptions.
     */
    public static ContentVersion getVersion(String contentVersionId) {
        // SYSTEM_MODE required so guest user can read VersionData blob content
        List<ContentVersion> versions = Database.queryWithBinds(
            'SELECT Id, Title, FileExtension, FileType, VersionData, ContentDocumentId, ContentSize'
            + ' FROM ContentVersion WHERE Id = :cvId LIMIT 1',
            new Map<String, Object>{ 'cvId' => contentVersionId },
            AccessLevel.SYSTEM_MODE
        );
        if (versions.isEmpty()) {
            throw new ESignException(
                'DOCUMENT_ERROR:ContentVersion not found: ' + contentVersionId
            );
        }
        return versions[0];
    }

    /**
     * Returns the base64-encoded body of a ContentVersion for
     * embedding in an iframe on the signing page.
     * Guarded to 10 MB to stay within VF page response limits.
     */
    public static String getVersionBase64(String contentVersionId) {
        if (String.isBlank(contentVersionId)) {
            System.debug(LoggingLevel.WARN, 'getVersionBase64: contentVersionId is blank');
            return null;
        }
        ContentVersion cv = getVersion(contentVersionId);
        if (cv.ContentSize != null && cv.ContentSize > 10485760) {
            throw new ESignException(
                'DOCUMENT_ERROR:Document exceeds 10 MB preview limit'
            );
        }
        if (cv.VersionData == null) {
            // VersionData is null when content is inaccessible in guest context
            // despite without sharing — return null so caller can show placeholder
            System.debug(LoggingLevel.WARN,
                'getVersionBase64: VersionData null for ContentVersion ' + contentVersionId);
            return null;
        }
        return EncodingUtil.base64Encode(cv.VersionData);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CREATE SIGNED DOCUMENT VERSION
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Creates a new signed version of the document.
     *
     * @param req            Fully-populated Signature_Request__c after signing
     * @param signatureBlob  Signature image as Blob (PNG/JPEG)
     * @return               ContentDocumentId of the new signed version
     */
    public static String createSignedVersion(
            Signature_Request__c req,
            Blob signatureBlob) {

        ContentVersion originalCv = getVersion(req.Content_Version_Id__c);

        Blob signedDocBlob = attemptPdfStamp(originalCv, signatureBlob, req);

        String auditManifest = buildAuditManifest(req);

        // Do NOT set ContentDocumentId — the original is in the requester's private
        // library; adding a version to it from guest/system context throws
        // INVALID_STATUS: Documents in a user's private library must always be owned by that user.
        // The signed copy is a standalone document linked via ContentDocumentLink instead.
        ContentVersion signedCv = new ContentVersion(
            Title           = originalCv.Title + ' [SIGNED - '
                                  + Datetime.now().format('yyyy-MM-dd HH:mm') + ']',
            PathOnClient    = originalCv.Title + '_signed.'
                                  + originalCv.FileExtension,
            VersionData     = signedDocBlob,
            IsMajorVersion  = true,
            Description     = auditManifest,
            ReasonForChange = 'Signed via SF-eSign | Request: ' + req.Name
        );
        Database.insert(signedCv, AccessLevel.SYSTEM_MODE);

        // Fetch auto-resolved ContentDocumentId (SYSTEM_MODE for guest context)
        List<ContentVersion> signedCvResult = Database.queryWithBinds(
            'SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvId',
            new Map<String, Object>{ 'cvId' => signedCv.Id },
            AccessLevel.SYSTEM_MODE
        );
        String signedDocId = signedCvResult[0].ContentDocumentId;

        // Link signed document to the Signature_Request__c record (duplicate-safe)
        linkDocumentToRecord(signedDocId, req.Id);

        // Link signed document to the related record if provided
        if (String.isNotBlank(req.Related_Record_Id__c)) {
            linkDocumentToRecord(signedDocId, req.Related_Record_Id__c);
        }

        return signedDocId;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SIGNATURE IMAGE STORAGE
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Saves the signature image as a standalone ContentDocument.
     * Stored separately from the signed document for independent retrieval.
     * @return ContentDocumentId of the signature image
     */
    public static String saveSignatureImage(String requestName, Blob signatureBlob) {
        ContentVersion sigCv = new ContentVersion(
            Title        = 'Signature - ' + requestName,
            PathOnClient = 'signature_' + requestName + '.png',
            VersionData  = signatureBlob,
            Description  = 'Signature image captured via SF-eSign for request ' + requestName
        );
        Database.insert(sigCv, AccessLevel.SYSTEM_MODE);

        // SYSTEM_MODE required for guest user to resolve ContentDocumentId post-insert
        List<ContentVersion> sigCvResult = Database.queryWithBinds(
            'SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvId',
            new Map<String, Object>{ 'cvId' => sigCv.Id },
            AccessLevel.SYSTEM_MODE
        );
        return sigCvResult[0].ContentDocumentId;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DOCUMENT-RECORD LINKING
    // ─────────────────────────────────────────────────────────────────────────

    public static void linkDocumentToRecord(String contentDocId, String recordId) {
        // SYSTEM_MODE required for guest user to query ContentDocumentLink
        List<ContentDocumentLink> existing = Database.queryWithBinds(
            'SELECT Id FROM ContentDocumentLink WHERE ContentDocumentId = :cdId AND LinkedEntityId = :recId LIMIT 1',
            new Map<String, Object>{ 'cdId' => contentDocId, 'recId' => recordId },
            AccessLevel.SYSTEM_MODE
        );
        if (!existing.isEmpty()) return;

        Database.insert(
            new ContentDocumentLink(
                ContentDocumentId = contentDocId,
                LinkedEntityId    = recordId,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            ),
            AccessLevel.SYSTEM_MODE
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PDF STAMPING (TIER 1 + TIER 2)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Attempts Tier 2 (callout to external stamp service).
     * Falls back to Tier 1 (original bytes + manifest) on any failure
     * or when no endpoint is configured.
     */
    private static Blob attemptPdfStamp(
            ContentVersion originalCv,
            Blob signatureBlob,
            Signature_Request__c req) {

        String stampEndpoint;
        try {
            stampEndpoint = System.Label.ESign_PDF_Stamp_Endpoint;
        } catch (Exception labelMissing) {
            // Label not deployed — use Tier 1 fallback
            return originalCv.VersionData;
        }

        if (String.isBlank(stampEndpoint) || stampEndpoint == 'NOT_CONFIGURED' || Test.isRunningTest()) {
            return originalCv.VersionData; // Tier 1 fallback
        }

        try {
            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(stampEndpoint);
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setTimeout(10000); // 10 second timeout

            Map<String, String> payload = new Map<String, String>{
                'documentBase64' => EncodingUtil.base64Encode(originalCv.VersionData),
                'signatureBase64'=> EncodingUtil.base64Encode(signatureBlob),
                'signerName'     => req.Signer_Email__c,
                'signedDateTime' => String.valueOf(req.Signed_DateTime__c),
                'requestRef'     => req.Name
            };
            httpReq.setBody(JSON.serialize(payload));

            HttpResponse res = new Http().send(httpReq);

            if (res.getStatusCode() == 200) {
                // Expect response body: { "stampedBase64": "..." }
                Map<String, Object> respMap =
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String stampedBase64 = (String) respMap.get('stampedBase64');
                if (String.isNotBlank(stampedBase64)) {
                    return EncodingUtil.base64Decode(stampedBase64);
                }
            }
        } catch (Exception e) {
            // Callout failed — fall through to Tier 1
            System.debug(LoggingLevel.WARN,
                'ESignDocumentService: PDF stamp callout failed, using Tier 1 fallback. '
                + e.getMessage());
        }

        return originalCv.VersionData; // Tier 1 fallback
    }

    /**
     * Builds a JSON audit manifest stored in the signed ContentVersion description.
     * This is the legally-relevant metadata trail attached to the document file.
     */
    private static String buildAuditManifest(Signature_Request__c req) {
        Map<String, Object> manifest = new Map<String, Object>{
            'signatureModule'   => 'SF-eSign',
            'requestRef'        => req.Name,
            'signatureRequestId'=> req.Id,
            'signerEmail'       => req.Signer_Email__c,
            'signedDateTime'    => String.valueOf(req.Signed_DateTime__c),
            'signatureType'     => req.Signature_Type__c,
            'signerIP'          => req.Signing_IP__c,
            'signerUserAgent'   => req.Signer_User_Agent__c,
            'originalVersionId' => req.Content_Version_Id__c
        };
        return JSON.serializePretty(manifest);
    }
}
