public with sharing class DocGen_SchemaService {

    public static List<DocGen_Wrappers.ObjectDescribeWrapper> getAllObjects() {
        List<DocGen_Wrappers.ObjectDescribeWrapper> result = new List<DocGen_Wrappers.ObjectDescribeWrapper>();
        // EntityDefinition SOQL is a single query and avoids the CPU limit caused
        // by calling Schema.getDescribe() on every object in the org (600-800+ calls).
        for (EntityDefinition ed : [
            SELECT QualifiedApiName, Label, IsCustomizable
            FROM   EntityDefinition
            WHERE  IsQueryable = true
            ORDER  BY Label ASC
            LIMIT  1000
        ]) {
            String apiName = ed.QualifiedApiName;
            String lbl     = ed.Label;
            // Skip objects with missing/internal labels (system-only objects)
            if (String.isBlank(lbl) || lbl.startsWith('__MISSING')) continue;
            // Skip audit/system objects not useful for document generation
            if (apiName.endsWith('Share')       || apiName.endsWith('History')      ||
                apiName.endsWith('Feed')        || apiName.endsWith('Tag')          ||
                apiName.endsWith('ChangeEvent') || apiName.endsWith('ViewStat')     ||
                apiName.endsWith('VoteStat')    || apiName.endsWith('DataCategorySelection')) {
                continue;
            }
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
