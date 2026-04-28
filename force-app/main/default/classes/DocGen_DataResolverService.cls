public with sharing class DocGen_DataResolverService {

    public class ResolvedDataWrapper {
        public Map<String, Object> primaryRecord;
        public Map<String, List<Map<String, Object>>> childRecords;
        public ResolvedDataWrapper() {
            this.primaryRecord = new Map<String, Object>();
            this.childRecords  = new Map<String, List<Map<String, Object>>>();
        }
    }

    public static ResolvedDataWrapper resolveData(
        String recordId,
        String primaryObject,
        List<DocGen_Wrappers.TokenMappingWrapper> mappings
    ) {
        ResolvedDataWrapper result = new ResolvedDataWrapper();
        if (String.isBlank(recordId) || String.isBlank(primaryObject) || mappings == null) {
            return result;
        }
        DocGen_SchemaService.validateObjectName(primaryObject);
        Map<String, Set<String>> fieldsByObject = groupFieldsByObject(mappings, primaryObject);

        Set<String> primaryFields = fieldsByObject.get(primaryObject);
        if (primaryFields == null) primaryFields = new Set<String>();
        String safeFieldList = buildFieldList(primaryObject, primaryFields);
        if (String.isNotBlank(safeFieldList)) {
            String soql = 'SELECT ' + safeFieldList
                        + ' FROM '  + primaryObject
                        + ' WHERE Id = :recordId'
                        + ' WITH SECURITY_ENFORCED'
                        + ' LIMIT 1';
            List<SObject> recs = Database.query(soql);
            if (!recs.isEmpty()) result.primaryRecord = flattenRecord(recs[0]);
        }

        Integer maxRows = 200;
        try {
            DocGen_Config__mdt cfg = DocGen_Config__mdt.getInstance('Default');
            if (cfg != null && cfg.Max_Repeating_Rows__c != null) {
                maxRows = Integer.valueOf(cfg.Max_Repeating_Rows__c);
            }
        } catch (Exception e) { /* use default */ }

        for (DocGen_Wrappers.TokenMappingWrapper m : mappings) {
            if (m.isRepeating != true || String.isBlank(m.repeatObject)) continue;
            String sectionKey = String.isNotBlank(m.token)
                ? m.token.replace('{{#', '').replace('}}', '').trim()
                : m.repeatObject;
            if (result.childRecords.containsKey(sectionKey)) continue;
            DocGen_SchemaService.validateObjectName(m.repeatObject);
            Set<String> childFields = fieldsByObject.get(m.repeatObject);
            if (childFields == null) childFields = new Set<String>();
            String childFieldList = buildFieldList(m.repeatObject, childFields);
            String lookupField = getParentLookupField(m.repeatObject, primaryObject);
            String childSoql = 'SELECT ' + childFieldList
                             + ' FROM '   + m.repeatObject
                             + ' WHERE '  + lookupField + ' = :recordId'
                             + ' WITH SECURITY_ENFORCED'
                             + ' LIMIT '  + maxRows;
            List<SObject> childList = Database.query(childSoql);
            System.debug(LoggingLevel.INFO, 'DocGen_DataResolverService: sectionKey=' + sectionKey + ', rows=' + childList.size());
            result.childRecords.put(sectionKey, flattenRecords(childList));
        }
        return result;
    }

    private static String buildFieldList(String objectName, Set<String> requestedFields) {
        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectName)?.getDescribe().fields.getMap();
        List<String> safe = new List<String>{ 'Id' };
        if (requestedFields == null) return String.join(safe, ', ');
        for (String f : requestedFields) {
            if (f == 'Id') continue;
            if (f.contains('.')) {
                if (validateTraversalPath(objectName, f)) safe.add(f);
            } else if (fieldMap != null && fieldMap.containsKey(f.toLowerCase())) {
                Schema.DescribeFieldResult dfr = fieldMap.get(f.toLowerCase()).getDescribe();
                if (dfr.isAccessible()) safe.add(dfr.getName());
            }
        }
        return String.join(safe, ', ');
    }

    private static Boolean validateTraversalPath(String rootObject, String path) {
        String[] parts = path.split('\\.');
        Schema.DescribeSObjectResult current =
            Schema.getGlobalDescribe().get(rootObject)?.getDescribe();
        for (Integer i = 0; i < parts.size() - 1; i++) {
            if (current == null) return false;
            Schema.DescribeFieldResult dfr =
                current.fields.getMap().get(parts[i].toLowerCase())?.getDescribe();
            if (dfr == null || dfr.getType() != Schema.DisplayType.REFERENCE) return false;
            if (!dfr.isAccessible()) return false;
            List<Schema.SObjectType> refs = dfr.getReferenceTo();
            if (refs.isEmpty()) return false;
            current = refs[0].getDescribe();
        }
        if (current == null) return false;
        Schema.DescribeFieldResult finalDfr =
            current.fields.getMap().get(parts[parts.size()-1].toLowerCase())?.getDescribe();
        return finalDfr != null && finalDfr.isAccessible();
    }

    private static Map<String, Set<String>> groupFieldsByObject(
        List<DocGen_Wrappers.TokenMappingWrapper> mappings,
        String primaryObject
    ) {
        Map<String, Set<String>> result = new Map<String, Set<String>>();
        result.put(primaryObject, new Set<String>());
        for (DocGen_Wrappers.TokenMappingWrapper m : mappings) {
            if (m.mappingType != 'FIELD') continue;
            String objKey = String.isNotBlank(m.sourceObject) ? m.sourceObject : primaryObject;
            if (!result.containsKey(objKey)) result.put(objKey, new Set<String>());
            String fieldKey = String.isNotBlank(m.relationshipPath) ? m.relationshipPath : m.sourceField;
            if (String.isNotBlank(fieldKey)) result.get(objKey).add(fieldKey);
        }
        return result;
    }

    private static Map<String, Object> flattenRecord(SObject rec) {
        Map<String, Object> flat = new Map<String, Object>();
        for (String field : rec.getPopulatedFieldsAsMap().keySet()) {
            Object val = rec.get(field);
            if (val instanceof SObject) {
                Map<String, Object> nested = flattenRecord((SObject)val);
                for (String nk : nested.keySet()) {
                    flat.put(field + '.' + nk, nested.get(nk));
                }
            } else {
                flat.put(field, val);
            }
        }
        return flat;
    }

    private static List<Map<String, Object>> flattenRecords(List<SObject> recs) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (SObject r : recs) result.add(flattenRecord(r));
        return result;
    }

    private static String getParentLookupField(String childObject, String parentObject) {
        Schema.DescribeSObjectResult childDr =
            Schema.getGlobalDescribe().get(childObject)?.getDescribe();
        if (childDr == null) throw new DocGen_Exception('Unknown child object: ' + childObject);
        for (Schema.SObjectField f : childDr.fields.getMap().values()) {
            Schema.DescribeFieldResult dfr = f.getDescribe();
            if (dfr.getType() == Schema.DisplayType.REFERENCE) {
                for (Schema.SObjectType ref : dfr.getReferenceTo()) {
                    if (ref.getDescribe().getName() == parentObject) return dfr.getName();
                }
            }
        }
        throw new DocGen_Exception('No lookup from ' + childObject + ' to ' + parentObject);
    }
}
