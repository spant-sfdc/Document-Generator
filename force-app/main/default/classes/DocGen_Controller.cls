public with sharing class DocGen_Controller {

    @AuraEnabled(cacheable=true)
    public static List<DocGen_Wrappers.ObjectDescribeWrapper> getObjects() {
        try {
            return DocGen_SchemaService.getAllObjects();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DocGen_Wrappers.FieldDescribeWrapper> getFields(String objectName) {
        try {
            DocGen_SchemaService.validateObjectName(objectName);
            return DocGen_SchemaService.getFields(objectName);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DocGen_Wrappers.ObjectDescribeWrapper> getRelatedObjects(String objectName) {
        try {
            DocGen_SchemaService.validateObjectName(objectName);
            return DocGen_SchemaService.getRelatedObjects(objectName);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<String> extractTokens(String contentVersionId) {
        try {
            return DocGen_TemplateService.extractTokens(contentVersionId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String uploadTemplate(String base64Content, String fileName) {
        try {
            return DocGen_TemplateService.uploadTemplateContent(base64Content, fileName);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static DocGen_Wrappers.TemplateSaveResultWrapper saveTemplateConfig(String configJson) {
        try {
            DocGen_Wrappers.TemplateConfigWrapper config =
                (DocGen_Wrappers.TemplateConfigWrapper)
                    JSON.deserialize(configJson, DocGen_Wrappers.TemplateConfigWrapper.class);
            return DocGen_TemplateService.saveTemplateConfig(config);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String generatePreview(String configJson) {
        try {
            DocGen_Wrappers.TemplateConfigWrapper config =
                (DocGen_Wrappers.TemplateConfigWrapper)
                    JSON.deserialize(configJson, DocGen_Wrappers.TemplateConfigWrapper.class);
            return DocGen_DocumentGeneratorService.generateHtml(config);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static DocGen_Wrappers.DocumentResponseWrapper generateDocument(
        String configJson,
        String format,
        String linkedRecordId
    ) {
        try {
            DocGen_Wrappers.TemplateConfigWrapper config =
                (DocGen_Wrappers.TemplateConfigWrapper)
                    JSON.deserialize(configJson, DocGen_Wrappers.TemplateConfigWrapper.class);
            String mergedHtml = DocGen_DocumentGeneratorService.generateHtml(config);
            Blob content;
            String fileName;

            if (format == 'PDF') {
                content  = DocGen_DocumentGeneratorService.generatePdf(mergedHtml);
                fileName = 'Document_' + Datetime.now().format('yyyyMMdd_HHmmss') + '.pdf';
            } else {
                content  = Blob.valueOf(mergedHtml);
                fileName = 'Document_' + Datetime.now().format('yyyyMMdd_HHmmss') + '.doc';
            }

            // Resolve Document_Template__c record ID from ContentVersion ID
            String tmplRecordId = null;
            if (String.isNotBlank(config.templateId)) {
                List<Document_Template__c> tmplList = [
                    SELECT Id FROM Document_Template__c
                    WHERE Template_Content_Version_Id__c = :config.templateId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                if (!tmplList.isEmpty()) tmplRecordId = tmplList[0].Id;
            }

            return DocGen_FileService.saveDocument(content, fileName, linkedRecordId, tmplRecordId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<Document_Template__c> getTemplates() {
        try {
            return [
                SELECT Id, Name, Primary_Object__c, Status__c, Version__c, Is_Active__c
                FROM Document_Template__c
                WHERE Is_Active__c = true
                WITH SECURITY_ENFORCED
                ORDER BY Name ASC
                LIMIT 200
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
