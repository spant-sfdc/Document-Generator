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
        // Use ordered list + seen set to preserve first-occurrence order before sorting.
        // Two separate passes so section markers always sort before field tokens.
        Set<String>  seen    = new Set<String>();
        List<String> result  = new List<String>();

        // Pass 1: repeating-section open markers  {{#ObjectName}}
        // Exclude {{#if ...}} — those are conditional directives, not mappable sections.
        Matcher sm = Pattern.compile('\\{\\{#([^{}]*)\\}\\}').matcher(text);
        while (sm.find()) {
            String name = sm.group(1).trim();
            if (name.startsWith('if ') || name == 'if') continue;
            String tok = '{{#' + name + '}}';
            if (!seen.contains(tok)) { seen.add(tok); result.add(tok); }
        }

        // Pass 2: plain field tokens  {{FieldName}}
        // Exclude sys.* — those are auto-resolved and need no mapping.
        Matcher fm = Pattern.compile('\\{\\{([^{}#/][^{}]*)\\}\\}').matcher(text);
        while (fm.find()) {
            String content = fm.group(1).trim();
            if (content.startsWith('sys.')) continue;
            String tok = '{{' + content + '}}';
            if (!seen.contains(tok)) { seen.add(tok); result.add(tok); }
        }

        result.sort();
        return result;
    }

    public static DocGen_Wrappers.TemplateSaveResultWrapper saveTemplateConfig(DocGen_Wrappers.TemplateConfigWrapper config) {
        if (!Schema.sObjectType.Document_Template__c.isCreateable()) {
            throw new DocGen_Exception('Insufficient access to create Document Templates.');
        }
        Document_Template__c tmpl = new Document_Template__c(
            Name                            = String.isNotBlank(config.templateName)
                                                ? config.templateName
                                                : 'Template-' + Datetime.now().format('yyyyMMdd-HHmmss'),
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

    public static DocGen_Wrappers.TemplateLoadResultWrapper loadTemplateConfig(String templateRecordId) {
        List<Document_Template__c> tmplList = [
            SELECT Id, Name, Primary_Object__c, Template_Content_Version_Id__c
            FROM Document_Template__c
            WHERE Id = :templateRecordId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (tmplList.isEmpty()) throw new DocGen_Exception('Template not found: ' + templateRecordId);
        Document_Template__c tmpl = tmplList[0];

        List<Document_Field_Mapping__c> mappingRecs = [
            SELECT Token_Name__c, Source_Object__c, Source_Field__c, Relationship_Path__c,
                   Mapping_Type__c, Static_Value__c, Format_Override__c,
                   Is_Repeating_Section__c, Repeat_Object__c
            FROM Document_Field_Mapping__c
            WHERE Template__c = :templateRecordId
            WITH SECURITY_ENFORCED
            ORDER BY Token_Name__c
        ];

        List<Document_Variable__c> varRecs = [
            SELECT Name, Variable_Type__c, Static_Value__c, Image_Content_Version_Id__c
            FROM Document_Variable__c
            WHERE Template__c = :templateRecordId
            WITH SECURITY_ENFORCED
        ];

        List<String> templateTokens = new List<String>();
        List<String> sysTokens      = new List<String>();
        try {
            templateTokens = extractTokens(tmpl.Template_Content_Version_Id__c);
            sysTokens      = extractSysTokens(tmpl.Template_Content_Version_Id__c);
        } catch (Exception e) { /* template file may have been deleted */ }

        // Infer parent/child objects from saved mappings
        Set<String> parentApiNames = new Set<String>();
        Set<String> childApiNames  = new Set<String>();
        for (Document_Field_Mapping__c m : mappingRecs) {
            if (m.Is_Repeating_Section__c == true && String.isNotBlank(m.Repeat_Object__c)) {
                childApiNames.add(m.Repeat_Object__c);
            } else if (m.Is_Repeating_Section__c != true
                    && String.isNotBlank(m.Source_Object__c)
                    && m.Source_Object__c != tmpl.Primary_Object__c
                    && String.isNotBlank(m.Relationship_Path__c)) {
                parentApiNames.add(m.Source_Object__c);
            }
        }

        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        List<DocGen_Wrappers.ObjectDescribeWrapper> parentObjects = new List<DocGen_Wrappers.ObjectDescribeWrapper>();
        List<DocGen_Wrappers.ObjectDescribeWrapper> childObjects  = new List<DocGen_Wrappers.ObjectDescribeWrapper>();
        for (String a : parentApiNames) {
            Schema.DescribeSObjectResult dr = gd.get(a)?.getDescribe();
            if (dr == null) continue;
            DocGen_Wrappers.ObjectDescribeWrapper w = new DocGen_Wrappers.ObjectDescribeWrapper();
            w.apiName = a; w.label = dr.getLabel(); w.isCustom = dr.isCustom();
            parentObjects.add(w);
        }
        for (String a : childApiNames) {
            Schema.DescribeSObjectResult dr = gd.get(a)?.getDescribe();
            if (dr == null) continue;
            DocGen_Wrappers.ObjectDescribeWrapper w = new DocGen_Wrappers.ObjectDescribeWrapper();
            w.apiName = a; w.label = dr.getLabel(); w.isCustom = dr.isCustom();
            childObjects.add(w);
        }

        DocGen_Wrappers.TemplateLoadResultWrapper result = new DocGen_Wrappers.TemplateLoadResultWrapper();
        result.templateId       = tmpl.Template_Content_Version_Id__c;
        result.templateRecordId = tmpl.Id;
        result.templateName     = tmpl.Name;
        result.primaryObject    = tmpl.Primary_Object__c;
        result.templateTokens   = templateTokens;
        result.sysTokens        = sysTokens;
        result.parentObjects    = parentObjects;
        result.childObjects     = childObjects;

        result.tokenMappings = new List<DocGen_Wrappers.TokenMappingWrapper>();
        for (Document_Field_Mapping__c m : mappingRecs) {
            DocGen_Wrappers.TokenMappingWrapper tw = new DocGen_Wrappers.TokenMappingWrapper();
            tw.token            = m.Token_Name__c;
            tw.sourceObject     = m.Source_Object__c;
            tw.sourceField      = m.Source_Field__c;
            tw.relationshipPath = m.Relationship_Path__c;
            tw.mappingType      = m.Mapping_Type__c;
            tw.staticValue      = m.Static_Value__c;
            tw.formatOverride   = m.Format_Override__c;
            tw.isRepeating      = m.Is_Repeating_Section__c;
            tw.repeatObject     = m.Repeat_Object__c;
            result.tokenMappings.add(tw);
        }

        result.variables = new List<DocGen_Wrappers.DocumentVariableWrapper>();
        for (Document_Variable__c v : varRecs) {
            DocGen_Wrappers.DocumentVariableWrapper dv = new DocGen_Wrappers.DocumentVariableWrapper();
            dv.variableName   = v.Name;
            dv.variableType   = v.Variable_Type__c;
            dv.staticValue    = v.Static_Value__c;
            dv.imageVersionId = v.Image_Content_Version_Id__c;
            result.variables.add(dv);
        }
        return result;
    }

    public static DocGen_Wrappers.TemplateSaveResultWrapper updateTemplateConfig(
        String templateRecordId, DocGen_Wrappers.TemplateConfigWrapper config) {

        List<Document_Template__c> tmplList = [
            SELECT Id, Name FROM Document_Template__c
            WHERE Id = :templateRecordId WITH SECURITY_ENFORCED LIMIT 1
        ];
        if (tmplList.isEmpty()) throw new DocGen_Exception('Template not found: ' + templateRecordId);
        Document_Template__c tmpl = tmplList[0];

        if (!Schema.sObjectType.Document_Template__c.isUpdateable())
            throw new DocGen_Exception('Insufficient access to update Document Templates.');
        if (String.isNotBlank(config.templateName))  tmpl.Name                           = config.templateName;
        if (String.isNotBlank(config.primaryObject)) tmpl.Primary_Object__c              = config.primaryObject;
        if (String.isNotBlank(config.templateId))    tmpl.Template_Content_Version_Id__c = config.templateId;
        update tmpl;

        List<Document_Field_Mapping__c> oldMappings = [
            SELECT Id FROM Document_Field_Mapping__c WHERE Template__c = :templateRecordId
        ];
        if (!oldMappings.isEmpty()) {
            if (!Schema.sObjectType.Document_Field_Mapping__c.isDeletable())
                throw new DocGen_Exception('Insufficient access to delete existing mappings.');
            delete oldMappings;
        }
        if (config.tokenMappings != null && !config.tokenMappings.isEmpty()) {
            List<Document_Field_Mapping__c> newMappings = new List<Document_Field_Mapping__c>();
            for (DocGen_Wrappers.TokenMappingWrapper tm : config.tokenMappings) {
                newMappings.add(new Document_Field_Mapping__c(
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
            insert newMappings;
        }

        List<Document_Variable__c> oldVars = [
            SELECT Id FROM Document_Variable__c WHERE Template__c = :templateRecordId
        ];
        if (!oldVars.isEmpty()) {
            if (!Schema.sObjectType.Document_Variable__c.isDeletable())
                throw new DocGen_Exception('Insufficient access to delete existing variables.');
            delete oldVars;
        }
        if (config.variables != null && !config.variables.isEmpty()) {
            List<Document_Variable__c> newVars = new List<Document_Variable__c>();
            for (DocGen_Wrappers.DocumentVariableWrapper dv : config.variables) {
                newVars.add(new Document_Variable__c(
                    Template__c                 = tmpl.Id,
                    Name                        = dv.variableName,
                    Variable_Type__c            = dv.variableType,
                    Static_Value__c             = dv.staticValue,
                    Image_Content_Version_Id__c = dv.imageVersionId
                ));
            }
            insert newVars;
        }

        tmpl = [SELECT Id, Name FROM Document_Template__c WHERE Id = :tmpl.Id LIMIT 1];
        DocGen_Wrappers.TemplateSaveResultWrapper result = new DocGen_Wrappers.TemplateSaveResultWrapper();
        result.templateId   = tmpl.Id;
        result.templateName = tmpl.Name;
        return result;
    }

    public static List<String> extractSysTokens(String contentVersionId) {
        return parseSysTokens(getTemplateText(contentVersionId));
    }

    public static List<String> parseSysTokens(String text) {
        if (String.isBlank(text)) return new List<String>();
        Set<String>  seen   = new Set<String>();
        List<String> result = new List<String>();
        Matcher m = Pattern.compile('\\{\\{(sys\\.[^{}]+)\\}\\}').matcher(text);
        while (m.find()) {
            String tok = '{{' + m.group(1).trim() + '}}';
            if (!seen.contains(tok)) { seen.add(tok); result.add(tok); }
        }
        result.sort();
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
