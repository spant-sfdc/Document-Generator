public class DocGen_Wrappers {

    public class ObjectDescribeWrapper implements Comparable {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isCustom;

        public Integer compareTo(Object other) {
            ObjectDescribeWrapper that = (ObjectDescribeWrapper) other;
            if (this.label == null && that.label == null) return 0;
            if (this.label == null) return 1;
            if (that.label == null) return -1;
            return this.label.compareTo(that.label);
        }
    }

    public class FieldDescribeWrapper {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String fieldType;
        @AuraEnabled public Boolean isAccessible;
    }

    public class TokenMappingWrapper {
        @AuraEnabled public String token;
        @AuraEnabled public String sourceObject;
        @AuraEnabled public String sourceField;
        @AuraEnabled public String relationshipPath;
        @AuraEnabled public String mappingType;
        @AuraEnabled public String staticValue;
        @AuraEnabled public String formatOverride;
        @AuraEnabled public Boolean isRepeating;
        @AuraEnabled public String repeatObject;
    }

    public class TemplateConfigWrapper {
        @AuraEnabled public String templateId;
        @AuraEnabled public String primaryObject;
        @AuraEnabled public String recordId;
        @AuraEnabled public List<TokenMappingWrapper> tokenMappings;
        @AuraEnabled public List<DocumentVariableWrapper> variables;
    }

    public class DocumentVariableWrapper {
        @AuraEnabled public String variableName;
        @AuraEnabled public String variableType;
        @AuraEnabled public String staticValue;
        @AuraEnabled public String imageVersionId;
        @AuraEnabled public String expression;
    }

    public class DocumentResponseWrapper {
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String base64Content;
        @AuraEnabled public String fileName;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;
    }

    public class TemplateSaveResultWrapper {
        @AuraEnabled public String templateId;
        @AuraEnabled public String templateName;
    }
}
