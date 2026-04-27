public with sharing class DocGen_FileService {

    public static DocGen_Wrappers.DocumentResponseWrapper saveDocument(
        Blob content,
        String fileName,
        String linkedRecordId,
        String templateId
    ) {
        DocGen_Wrappers.DocumentResponseWrapper response = new DocGen_Wrappers.DocumentResponseWrapper();
        try {
            if (!Schema.sObjectType.ContentVersion.isCreateable()) {
                throw new DocGen_Exception('Insufficient access to create files.');
            }
            ContentVersion cv = new ContentVersion(
                Title          = fileName,
                PathOnClient   = fileName,
                VersionData    = content,
                IsMajorVersion = true
            );
            insert cv;

            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
            String docId = cv.ContentDocumentId;

            if (String.isNotBlank(linkedRecordId)) {
                ContentDocumentLink cdl = new ContentDocumentLink(
                    ContentDocumentId = docId,
                    LinkedEntityId    = linkedRecordId,
                    ShareType         = 'V',
                    Visibility        = 'AllUsers'
                );
                insert cdl;
            }

            Document_Generation_Log__c log = new Document_Generation_Log__c(
                Record_Id__c                  = linkedRecordId,
                Generated_At__c               = System.now(),
                Status__c                     = 'Success',
                Output_Content_Document_Id__c = docId
            );
            if (String.isNotBlank(templateId)) {
                String tmplPrefix = Document_Template__c.SObjectType.getDescribe().getKeyPrefix();
                if (templateId.startsWith(tmplPrefix)) {
                    log.Template__c = templateId;
                }
            }
            insert log;

            response.contentDocumentId = docId;
            response.base64Content     = EncodingUtil.base64Encode(content);
            response.fileName          = fileName;
            response.success           = true;

        } catch (Exception e) {
            response.success      = false;
            response.errorMessage = e.getMessage();
            try {
                Document_Generation_Log__c errLog = new Document_Generation_Log__c(
                    Record_Id__c   = linkedRecordId,
                    Generated_At__c = System.now(),
                    Status__c      = 'Failed',
                    Error_Message__c = e.getMessage()
                );
                insert errLog;
            } catch (Exception le) { /* suppress log insert failure */ }
        }
        return response;
    }
}
