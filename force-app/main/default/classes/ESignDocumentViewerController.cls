/**
 * Apex controller for the eSignDocumentViewer LWC.
 * Returns document versions + signature image metadata for the record page split-screen viewer.
 */
public with sharing class ESignDocumentViewerController {

    public class ViewerData {
        @AuraEnabled public String        status;
        @AuraEnabled public String        recipientEmail;
        @AuraEnabled public String        signerEmail;
        @AuraEnabled public String        signedDatetime;
        @AuraEnabled public String        signatureType;
        @AuraEnabled public String        documentId;       // ContentDocumentId
        @AuraEnabled public String        previewVersionId; // latest ContentVersionId
        @AuraEnabled public String        sigImageVersionId;
        @AuraEnabled public List<VersionRow> versions;
    }

    public class VersionRow {
        @AuraEnabled public String  id;
        @AuraEnabled public String  title;
        @AuraEnabled public Integer versionNumber;
        @AuraEnabled public String  modifiedDate;
        @AuraEnabled public Boolean isSigned;
    }

    @AuraEnabled(cacheable=true)
    public static ViewerData getViewerData(String recordId) {
        Signature_Request__c req = [
            SELECT  Id, Status__c, Document_Id__c, Content_Version_Id__c,
                    Signature_Image_Id__c, Signature_Type__c,
                    Signer_Email__c, Signed_DateTime__c, Recipient_Email__c
            FROM    Signature_Request__c
            WHERE   Id = :recordId
            WITH    SECURITY_ENFORCED
            LIMIT   1
        ];

        ViewerData vd       = new ViewerData();
        vd.status           = req.Status__c;
        vd.recipientEmail   = req.Recipient_Email__c;
        vd.signerEmail      = req.Signer_Email__c;
        vd.signedDatetime   = req.Signed_DateTime__c != null
            ? req.Signed_DateTime__c.format('dd MMM yyyy, HH:mm z')
            : null;
        vd.signatureType    = req.Signature_Type__c;
        vd.documentId       = req.Document_Id__c;
        vd.versions         = new List<VersionRow>();

        if (String.isNotBlank(req.Document_Id__c)) {
            List<ContentVersion> cvs = [
                SELECT  Id, Title, VersionNumber, ContentModifiedDate, ReasonForChange
                FROM    ContentVersion
                WHERE   ContentDocumentId = :req.Document_Id__c
                ORDER BY VersionNumber DESC
            ];
            for (ContentVersion cv : cvs) {
                VersionRow row    = new VersionRow();
                row.id            = cv.Id;
                row.title         = cv.Title;
                row.versionNumber = Integer.valueOf(cv.VersionNumber);
                row.modifiedDate  = cv.ContentModifiedDate != null
                    ? cv.ContentModifiedDate.format('dd MMM yyyy')
                    : '';
                row.isSigned      = cv.ReasonForChange != null
                    && cv.ReasonForChange.containsIgnoreCase('SF-eSign');
                vd.versions.add(row);
            }
            if (!cvs.isEmpty()) {
                vd.previewVersionId = cvs[0].Id; // latest (signed if exists)
            }
        }

        if (String.isNotBlank(req.Signature_Image_Id__c)) {
            List<ContentVersion> sigs = [
                SELECT  Id
                FROM    ContentVersion
                WHERE   ContentDocumentId = :req.Signature_Image_Id__c
                AND     IsLatest = true
                LIMIT   1
            ];
            if (!sigs.isEmpty()) {
                vd.sigImageVersionId = sigs[0].Id;
            }
        }

        return vd;
    }

    /**
     * Returns base64-encoded VersionData for a ContentVersion so the LWC can
     * embed it as data:application/pdf;base64,... in an iframe — avoiding the
     * /sfc/servlet.shepherd download URL that triggers a file download instead
     * of an inline preview.
     * Capped at 10 MB; returns null for oversized or missing content.
     */
    @AuraEnabled(cacheable=true)
    public static String getVersionBase64(String versionId) {
        if (String.isBlank(versionId)) return null;
        List<ContentVersion> cvList = [
            SELECT VersionData, ContentSize, FileType
            FROM   ContentVersion
            WHERE  Id = :versionId
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        if (cvList.isEmpty() || cvList[0].VersionData == null) return null;
        if (cvList[0].ContentSize != null && cvList[0].ContentSize > 10485760) return null;
        return EncodingUtil.base64Encode(cvList[0].VersionData);
    }
}
