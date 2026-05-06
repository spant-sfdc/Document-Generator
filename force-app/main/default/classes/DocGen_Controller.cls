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

    /**
     * Returns all lookup fields on primaryObject that point to parentObject.
     * Result: [{label, relationshipName}] — one entry per qualifying lookup field.
     * Used by the mapping builder to let users choose the correct relationship
     * when a primary object has multiple lookups to the same parent (e.g. two
     * Account lookups on Opportunity).
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getParentRelationships(
        String primaryObject, String parentObject
    ) {
        try {
            DocGen_SchemaService.validateObjectName(primaryObject);
            DocGen_SchemaService.validateObjectName(parentObject);
            return DocGen_SchemaService.getParentRelationships(primaryObject, parentObject);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDemoModeConfig() {
        try {
            List<Demo_Mode__mdt> rows = [
                SELECT Is_Enabled__c, Scenario_Name__c, Auto_Mapping_JSON__c, Auto_Variables_JSON__c
                FROM   Demo_Mode__mdt
                WHERE  Is_Enabled__c = true
                LIMIT  1
            ];
            if (rows.isEmpty()) {
                return new Map<String, Object>{ 'isEnabled' => false };
            }
            Demo_Mode__mdt cfg = rows[0];
            return new Map<String, Object>{
                'isEnabled'         => cfg.Is_Enabled__c,
                'scenarioName'      => cfg.Scenario_Name__c,
                'autoMappingJson'   => cfg.Auto_Mapping_JSON__c,
                'autoVariablesJson' => cfg.Auto_Variables_JSON__c
            };
        } catch (Exception e) {
            return new Map<String, Object>{ 'isEnabled' => false };
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

    /**
     * Step 1 of two-step PDF generation.
     *
     * Generates merged HTML (with print styles) and stores it as a temp
     * ContentVersion so it is committed before generateDocument() fires
     * getContentAsPDF(). getContentAsPDF() runs in a separate execution
     * context and cannot see same-transaction DML — splitting into two
     * @AuraEnabled calls ensures the ContentVersion is already committed
     * when the VF controller queries it.
     *
     * @return ContentVersion Id of the temp HTML record
     */
    @AuraEnabled
    public static String storeMergedHtml(String configJson) {
        try {
            DocGen_Wrappers.TemplateConfigWrapper config =
                (DocGen_Wrappers.TemplateConfigWrapper)
                    JSON.deserialize(configJson, DocGen_Wrappers.TemplateConfigWrapper.class);
            String styledHtml = DocGen_DocumentGeneratorService.getStyledHtml(config);
            ContentVersion cv = new ContentVersion(
                Title          = 'DocGen_TempPdf_' + Datetime.now().format('yyyyMMddHHmmss'),
                PathOnClient   = 'docgen_temp.html',
                VersionData    = Blob.valueOf(styledHtml),
                IsMajorVersion = false
            );
            insert cv;
            System.debug(LoggingLevel.INFO, 'DocGen_Controller.storeMergedHtml: cvId=' + cv.Id);
            return cv.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Step 2 of two-step PDF generation.
     *
     * For PDF format: accepts the ContentVersion Id returned by storeMergedHtml()
     * (committed in the prior transaction), generates the PDF, then deletes the
     * temp ContentVersion. For other formats: generates HTML inline as before.
     */
    @AuraEnabled
    public static DocGen_Wrappers.DocumentResponseWrapper generateDocument(
        String configJson,
        String format,
        String linkedRecordId,
        String tempCvId
    ) {
        try {
            DocGen_Wrappers.TemplateConfigWrapper config =
                (DocGen_Wrappers.TemplateConfigWrapper)
                    JSON.deserialize(configJson, DocGen_Wrappers.TemplateConfigWrapper.class);
            Blob content;
            String fileName;

            if (format == 'PDF') {
                if (String.isBlank(tempCvId)) {
                    throw new DocGen_Exception('tempCvId is required for PDF generation');
                }
                content  = DocGen_DocumentGeneratorService.generatePdfFromCv(tempCvId);
                fileName = 'Document_' + Datetime.now().format('yyyyMMdd_HHmmss') + '.pdf';
            } else {
                String mergedHtml = DocGen_DocumentGeneratorService.generateHtml(config);
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

            DocGen_Wrappers.DocumentResponseWrapper result =
                DocGen_FileService.saveDocument(content, fileName, linkedRecordId, tmplRecordId);

            // Clean up the temp ContentVersion created by storeMergedHtml()
            if (format == 'PDF' && String.isNotBlank(tempCvId)) {
                try {
                    List<ContentVersion> cvs = [
                        SELECT ContentDocumentId FROM ContentVersion WHERE Id = :tempCvId LIMIT 1
                    ];
                    if (!cvs.isEmpty()) {
                        delete new ContentDocument(Id = cvs[0].ContentDocumentId);
                    }
                } catch (Exception cleanupEx) {
                    System.debug(LoggingLevel.WARN,
                        'DocGen_Controller: temp CV cleanup failed: ' + cleanupEx.getMessage());
                }
            }

            return result;
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

    @AuraEnabled
    public static List<String> extractVariableTokens(String contentVersionId) {
        try {
            return DocGen_TemplateService.extractVariableTokens(contentVersionId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Returns up to 10 most-recent successfully generated documents linked to a record,
     * ordered newest-first. Used by the eSignButton component to pre-populate the document
     * picker without requiring the user to browse Salesforce Files manually.
     */
    @AuraEnabled
    public static List<Map<String, String>> getGeneratedDocumentsForRecord(String recordId) {
        if (String.isBlank(recordId)) return new List<Map<String, String>>();
        List<Map<String, String>> results = new List<Map<String, String>>();
        try {
            for (Document_Generation_Log__c log : [
                SELECT Output_Content_Document_Id__c,
                       Generated_At__c,
                       Template__r.Name
                FROM   Document_Generation_Log__c
                WHERE  Record_Id__c                  = :recordId
                AND    Output_Content_Document_Id__c != null
                AND    Status__c                     = 'Success'
                WITH   SECURITY_ENFORCED
                ORDER  BY Generated_At__c DESC
                LIMIT  10
            ]) {
                results.add(new Map<String, String>{
                    'contentDocumentId' => log.Output_Content_Document_Id__c,
                    'generatedAt'       => log.Generated_At__c != null
                                            ? String.valueOf(log.Generated_At__c) : '',
                    'templateName'      => log.Template__r != null && log.Template__r.Name != null
                                            ? log.Template__r.Name : 'Document'
                });
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
        return results;
    }
}
