public with sharing class DocGen_TemplateService {

    public static String getTemplateText(String contentVersionId) {
        List<ContentVersion> cvList = [
            SELECT VersionData FROM ContentVersion
            WHERE Id = :contentVersionId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (cvList.isEmpty()) throw new DocGen_Exception('Template not found: ' + contentVersionId);
        return cvList[0].VersionData.toString();
    }

    public static Blob getTemplateBlob(String contentVersionId) {
        List<ContentVersion> cvList = [
            SELECT VersionData FROM ContentVersion
            WHERE Id = :contentVersionId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (cvList.isEmpty()) throw new DocGen_Exception('Template not found: ' + contentVersionId);
        return cvList[0].VersionData;
    }

    public static List<String> extractTokens(String contentVersionId) {
        String templateText = getTemplateText(contentVersionId);
        return parseTokens(templateText);
    }

    public static List<String> parseTokens(String text) {
        Set<String> tokens = new Set<String>();
        Pattern simplePattern = Pattern.compile('\\{\\{([^{}#/][^{}]*)\\}\\}');
        Matcher m = simplePattern.matcher(text);
        while (m.find()) {
            tokens.add('{{' + m.group(1).trim() + '}}');
        }
        Pattern sectionPattern = Pattern.compile('\\{\\{#([^{}]*)\\}\\}');
        Matcher sm = sectionPattern.matcher(text);
        while (sm.find()) {
            tokens.add('{{#' + sm.group(1).trim() + '}}');
        }
        return new List<String>(tokens);
    }

    public static DocGen_Wrappers.TemplateSaveResultWrapper saveTemplateConfig(DocGen_Wrappers.TemplateConfigWrapper config) {
        if (!Schema.sObjectType.Document_Template__c.isCreateable()) {
            throw new DocGen_Exception('Insufficient access to create Document Templates.');
        }
        Document_Template__c tmpl = new Document_Template__c(
            Primary_Object__c               = config.primaryObject,
            Template_Content_Version_Id__c  = config.templateId,
            Status__c                       = 'Active',
            Version__c                      = 1,
            Is_Active__c                    = true
        );
        insert tmpl;

        if (config.tokenMappings != null && !config.tokenMappings.isEmpty()) {
            List<Document_Field_Mapping__c> mappings = new List<Document_Field_Mapping__c>();
            for (DocGen_Wrappers.TokenMappingWrapper tm : config.tokenMappings) {
                mappings.add(new Document_Field_Mapping__c(
                    Template__c             = tmpl.Id,
                    Token_Name__c           = tm.token,
                    Source_Object__c        = tm.sourceObject,
                    Source_Field__c         = tm.sourceField,
                    Relationship_Path__c    = tm.relationshipPath,
                    Mapping_Type__c         = tm.mappingType,
                    Static_Value__c         = tm.staticValue,
                    Format_Override__c      = tm.formatOverride,
                    Is_Repeating_Section__c = tm.isRepeating == true,
                    Repeat_Object__c        = tm.repeatObject
                ));
            }
            insert mappings;
        }

        if (config.variables != null && !config.variables.isEmpty()) {
            List<Document_Variable__c> vars = new List<Document_Variable__c>();
            for (DocGen_Wrappers.DocumentVariableWrapper dv : config.variables) {
                vars.add(new Document_Variable__c(
                    Template__c              = tmpl.Id,
                    Name                     = dv.variableName,
                    Variable_Type__c         = dv.variableType,
                    Static_Value__c          = dv.staticValue,
                    Image_Content_Version_Id__c = dv.imageVersionId
                ));
            }
            insert vars;
        }
        tmpl = [SELECT Id, Name FROM Document_Template__c WHERE Id = :tmpl.Id LIMIT 1];
        DocGen_Wrappers.TemplateSaveResultWrapper result = new DocGen_Wrappers.TemplateSaveResultWrapper();
        result.templateId   = tmpl.Id;
        result.templateName = tmpl.Name;
        return result;
    }

    public static String uploadTemplateContent(String base64Content, String fileName) {
        if (!Schema.sObjectType.ContentVersion.isCreateable()) {
            throw new DocGen_Exception('Insufficient access to upload files.');
        }
        Blob fileBlob = EncodingUtil.base64Decode(base64Content);
        ContentVersion cv = new ContentVersion(
            Title        = fileName,
            PathOnClient = fileName,
            VersionData  = fileBlob,
            IsMajorVersion = true
        );
        insert cv;
        return cv.Id;
    }
}
