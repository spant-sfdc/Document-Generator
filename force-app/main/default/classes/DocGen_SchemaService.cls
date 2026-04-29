public with sharing class DocGen_SchemaService {

    // Search by filtering Schema.getGlobalDescribe() keys (no SOQL, no EntityDefinition,
    // no queryMore issues). Step 1 is a cheap string-contains on map keys; Step 2
    // calls getDescribe() only on the small set of matched candidates.
    public static List<DocGen_Wrappers.ObjectDescribeWrapper> searchObjects(String searchTerm) {
        List<DocGen_Wrappers.ObjectDescribeWrapper> result = new List<DocGen_Wrappers.ObjectDescribeWrapper>();
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) return result;
        String lower = searchTerm.trim().toLowerCase();

        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

        List<String> candidates = new List<String>();
        for (String key : gd.keySet()) {
            if (!key.contains(lower)) continue;
            if (key.endsWith('share')       || key.endsWith('history')     ||
                key.endsWith('feed')        || key.endsWith('tag')         ||
                key.endsWith('changeevent') || key.endsWith('votestat')    ||
                key.endsWith('viewstat')) continue;
            candidates.add(key);
        }
        candidates.sort();

        for (String key : candidates) {
            if (result.size() >= 30) break;
            Schema.DescribeSObjectResult dr = gd.get(key).getDescribe();
            if (!dr.isQueryable() || !dr.isAccessible()) continue;
            String lbl = dr.getLabel();
            if (String.isBlank(lbl) || lbl.startsWith('__MISSING')) continue;
            DocGen_Wrappers.ObjectDescribeWrapper w = new DocGen_Wrappers.ObjectDescribeWrapper();
            w.apiName  = dr.getName();
            w.label    = lbl;
            w.isCustom = dr.isCustom();
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
