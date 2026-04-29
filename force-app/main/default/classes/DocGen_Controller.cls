public with sharing class DocGen_Controller {

    @AuraEnabled(cacheable=true)
    public static List<DocGen_Wrappers.ObjectDescribeWrapper> searchObjects(String searchTerm) {
        try {
            return DocGen_SchemaService.searchObjects(searchTerm);
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
    public static String storePreviewHtml(String htmlContent) {
        try {
            ContentVersion cv = new ContentVersion();
            cv.Title          = 'DocGen_Preview_' + Datetime.now().format('yyyyMMdd_HHmmss');
            cv.PathOnClient   = 'DocGen_Preview.html';
            cv.VersionData    = Blob.valueOf(htmlContent);
            cv.IsMajorVersion = false;
            insert cv;
            return cv.Id;
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

    @AuraEnabled(cacheable=true)
    public static DocGen_Wrappers.TemplateLoadResultWrapper getTemplateConfig(String templateRecordId) {
        try {
            return DocGen_TemplateService.loadTemplateConfig(templateRecordId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Document_Template__c> getTemplatesForObject(String objectName) {
        try {
            if (String.isNotBlank(objectName)) {
                DocGen_SchemaService.validateObjectName(objectName);
                return [
                    SELECT Id, Name, Primary_Object__c, Status__c
                    FROM Document_Template__c
                    WHERE Is_Active__c = true AND Primary_Object__c = :objectName
                    WITH SECURITY_ENFORCED
                    ORDER BY Name ASC
                    LIMIT 100
                ];
            }
            return [
                SELECT Id, Name, Primary_Object__c, Status__c
                FROM Document_Template__c
                WHERE Is_Active__c = true
                WITH SECURITY_ENFORCED
                ORDER BY Name ASC
                LIMIT 100
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getSystemVariableValues() {
        try {
            Map<String, String> result = new Map<String, String>{
                'sys.today'       => Date.today().format(),
                'sys.currentUser' => UserInfo.getName(),
                'sys.orgName'     => UserInfo.getOrganizationName(),
                'sys.userEmail'   => UserInfo.getUserEmail(),
                'sys.orgEIN'      => '',
                'sys.orgAddress'  => '',
                'sys.orgPhone'    => '',
                'sys.orgWebsite'  => ''
            };
            try {
                DocGen_Config__mdt cfg = DocGen_Config__mdt.getInstance('Default');
                if (cfg != null) {
                    if (String.isNotBlank(cfg.Org_Display_Name__c)) result.put('sys.orgName',    cfg.Org_Display_Name__c);
                    if (String.isNotBlank(cfg.Org_EIN__c))          result.put('sys.orgEIN',     cfg.Org_EIN__c);
                    if (String.isNotBlank(cfg.Org_Address__c))      result.put('sys.orgAddress', cfg.Org_Address__c);
                    if (String.isNotBlank(cfg.Org_Phone__c))        result.put('sys.orgPhone',   cfg.Org_Phone__c);
                    if (String.isNotBlank(cfg.Org_Website__c))      result.put('sys.orgWebsite', cfg.Org_Website__c);
                }
            } catch (Exception ex) { /* use UserInfo defaults */ }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static DocGen_Wrappers.TemplateSaveResultWrapper updateTemplateConfig(
        String templateRecordId, String configJson) {
        try {
            DocGen_Wrappers.TemplateConfigWrapper config =
                (DocGen_Wrappers.TemplateConfigWrapper)
                    JSON.deserialize(configJson, DocGen_Wrappers.TemplateConfigWrapper.class);
            return DocGen_TemplateService.updateTemplateConfig(templateRecordId, config);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<String> extractSysTokens(String contentVersionId) {
        try {
            return DocGen_TemplateService.extractSysTokens(contentVersionId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
