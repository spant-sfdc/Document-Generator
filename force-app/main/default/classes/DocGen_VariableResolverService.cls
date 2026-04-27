public with sharing class DocGen_VariableResolverService {

    public static Map<String, String> resolve(
        List<DocGen_Wrappers.DocumentVariableWrapper> variables
    ) {
        Map<String, String> resolved = new Map<String, String>();

        resolved.put('today',       Date.today().format());
        resolved.put('currentUser', UserInfo.getName());
        resolved.put('orgName',     UserInfo.getOrganizationName());
        resolved.put('userEmail',   UserInfo.getUserEmail());

        try {
            DocGen_Config__mdt cfg = DocGen_Config__mdt.getInstance('Default');
            if (cfg != null) {
                if (String.isNotBlank(cfg.Org_Display_Name__c)) resolved.put('orgName',    cfg.Org_Display_Name__c);
                if (String.isNotBlank(cfg.Org_EIN__c))          resolved.put('orgEIN',     cfg.Org_EIN__c);
                if (String.isNotBlank(cfg.Org_Address__c))      resolved.put('orgAddress', cfg.Org_Address__c);
                if (String.isNotBlank(cfg.Org_Phone__c))        resolved.put('orgPhone',   cfg.Org_Phone__c);
                if (String.isNotBlank(cfg.Org_Website__c))      resolved.put('orgWebsite', cfg.Org_Website__c);
            }
        } catch (Exception e) { /* use defaults */ }

        if (variables == null) return resolved;

        for (DocGen_Wrappers.DocumentVariableWrapper v : variables) {
            if (String.isBlank(v.variableName)) continue;
            switch on v.variableType {
                when 'CONSTANT'     { resolved.put(v.variableName, v.staticValue != null ? v.staticValue : ''); }
                when 'SYSTEM_DATE'  { resolved.put(v.variableName, Date.today().format()); }
                when 'CURRENT_USER' { resolved.put(v.variableName, UserInfo.getName()); }
                when 'ORG_NAME'     { resolved.put(v.variableName, UserInfo.getOrganizationName()); }
                when 'IMAGE'        { resolved.put(v.variableName, resolveImageToken(v.imageVersionId)); }
                when else           { resolved.put(v.variableName, v.staticValue != null ? v.staticValue : ''); }
            }
        }
        return resolved;
    }

    private static String resolveImageToken(String versionId) {
        if (String.isBlank(versionId)) return '';
        try {
            List<ContentVersion> cvList = [
                SELECT VersionData, FileType FROM ContentVersion
                WHERE Id = :versionId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (cvList.isEmpty()) return '';
            String base64 = EncodingUtil.base64Encode(cvList[0].VersionData);
            String mime   = 'image/' + cvList[0].FileType.toLowerCase();
            return '<img src="data:' + mime + ';base64,' + base64 + '" style="max-width:100%;" />';
        } catch (Exception e) { return ''; }
    }
}
