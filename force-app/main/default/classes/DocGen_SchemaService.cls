public with sharing class DocGen_SchemaService {

    // Server-side search: fires a scoped EntityDefinition SOQL query for each
    // keystroke. LIMIT 50 guarantees results always fit in one batch, which is
    // required because EntityDefinition does not support queryMore().
    public static List<DocGen_Wrappers.ObjectDescribeWrapper> searchObjects(String searchTerm) {
        List<DocGen_Wrappers.ObjectDescribeWrapper> result = new List<DocGen_Wrappers.ObjectDescribeWrapper>();
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) return result;
        String term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        for (EntityDefinition ed : [
            SELECT QualifiedApiName, Label
            FROM   EntityDefinition
            WHERE  IsQueryable = true
            AND    (Label LIKE :term OR QualifiedApiName LIKE :term)
            ORDER  BY Label ASC
            LIMIT  50
        ]) {
            String apiName = ed.QualifiedApiName;
            String lbl     = ed.Label;
            if (String.isBlank(lbl) || lbl.startsWith('__MISSING')) continue;
            if (apiName.endsWith('Share')       || apiName.endsWith('History')  ||
                apiName.endsWith('Feed')        || apiName.endsWith('Tag')      ||
                apiName.endsWith('ChangeEvent') || apiName.endsWith('VoteStat') ||
                apiName.endsWith('ViewStat')) continue;
            DocGen_Wrappers.ObjectDescribeWrapper w = new DocGen_Wrappers.ObjectDescribeWrapper();
            w.apiName  = apiName;
            w.label    = lbl;
            w.isCustom = apiName.endsWith('__c');
            result.add(w);
        }
        return result;
    }

    public static List<DocGen_Wrappers.FieldDescribeWrapper> getFields(String objectName) {
        validateObjectName(objectName);
        Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(objectName);
        if (sobjType == null) throw new DocGen_Exception('Unknown object: ' + objectName);
        List<DocGen_Wrappers.FieldDescribeWrapper> result = new List<DocGen_Wrappers.FieldDescribeWrapper>();
        Map<String, Schema.SObjectField> fieldMap = sobjType.getDescribe().fields.getMap();
        for (String fKey : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fKey).getDescribe();
            if (!dfr.isAccessible()) continue;
            DocGen_Wrappers.FieldDescribeWrapper w = new DocGen_Wrappers.FieldDescribeWrapper();
            w.apiName      = dfr.getName();
            w.label        = dfr.getLabel();
            w.fieldType    = String.valueOf(dfr.getType());
            w.isAccessible = true;
            result.add(w);
        }
        return result;
    }

    public static List<DocGen_Wrappers.ObjectDescribeWrapper> getRelatedObjects(String objectName) {
        validateObjectName(objectName);
        Schema.DescribeSObjectResult dr = Schema.getGlobalDescribe().get(objectName)?.getDescribe();
        if (dr == null) throw new DocGen_Exception('Unknown object: ' + objectName);
        List<DocGen_Wrappers.ObjectDescribeWrapper> result = new List<DocGen_Wrappers.ObjectDescribeWrapper>();
        Set<String> added = new Set<String>();

        for (Schema.SObjectField f : dr.fields.getMap().values()) {
            Schema.DescribeFieldResult dfr = f.getDescribe();
            if (dfr.getType() == Schema.DisplayType.REFERENCE && dfr.isAccessible()) {
                for (Schema.SObjectType ref : dfr.getReferenceTo()) {
                    String refName = ref.getDescribe().getName();
                    if (added.contains(refName)) continue;
                    added.add(refName);
                    DocGen_Wrappers.ObjectDescribeWrapper w = new DocGen_Wrappers.ObjectDescribeWrapper();
                    w.apiName = refName;
                    w.label   = ref.getDescribe().getLabel() + ' (Parent)';
                    w.isCustom = ref.getDescribe().isCustom();
                    result.add(w);
                }
            }
        }

        for (Schema.ChildRelationship cr : dr.getChildRelationships()) {
            Schema.DescribeSObjectResult childDr = cr.getChildSObject().getDescribe();
            if (!childDr.isAccessible()) continue;
            String childName = childDr.getName();
            if (added.contains(childName)) continue;
            added.add(childName);
            DocGen_Wrappers.ObjectDescribeWrapper w = new DocGen_Wrappers.ObjectDescribeWrapper();
            w.apiName = childName;
            w.label   = childDr.getLabel() + ' (Child)';
            w.isCustom = childDr.isCustom();
            result.add(w);
        }
        return result;
    }

    public static void validateObjectName(String name) {
        if (String.isBlank(name) || !Pattern.matches('[a-zA-Z0-9_]+', name)) {
            throw new DocGen_Exception('Invalid object/field name: ' + name);
        }
    }
}
