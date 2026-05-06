public with sharing class DocGen_VariableResolverService {

    /**
     * Resolves variables with live record data context.
     * Supports EXPRESSION type: evaluates simple comparisons against primaryData fields.
     * Supported operators: >, <, >=, <=, ==, !=  and right-hand-side "null".
     * Falls back to resolve() for all non-EXPRESSION variable types.
     */
    public static Map<String, String> resolveWithData(
        List<DocGen_Wrappers.DocumentVariableWrapper> variables,
        Map<String, Object> primaryData
    ) {
        Map<String, String> resolved = resolve(variables);
        if (variables == null || primaryData == null) return resolved;

        for (DocGen_Wrappers.DocumentVariableWrapper v : variables) {
            if (String.isBlank(v.variableName)
                    || (v.variableType != 'EXPRESSION' && v.variableType != 'BOOLEAN')) continue;
            // expression field is preferred; Static_Value__c is used as fallback storage
            String expr = String.isNotBlank(v.expression) ? v.expression : v.staticValue;
            if (String.isBlank(expr)) continue;
            try {
                Boolean result = evaluateExpression(expr.trim(), primaryData);
                resolved.put(v.variableName, result ? 'true' : 'false');
            } catch (Exception e) {
                resolved.put(v.variableName, 'false');
            }
        }
        return resolved;
    }

    // Evaluates "FieldApiName operator value" against primaryData.
    // Numeric and string comparisons are both supported.
    // Right-hand side "null" is valid with == and !=.
    private static Boolean evaluateExpression(String expr, Map<String, Object> data) {
        String[] ops = new String[]{ '>=', '<=', '!=', '==', '>', '<' };
        for (String op : ops) {
            Integer idx = expr.indexOf(op);
            if (idx < 0) continue;
            String lhs    = expr.substring(0, idx).trim();
            String rhs    = expr.substring(idx + op.length()).trim().replace('\'', '').trim();
            Object leftVal = data.get(lhs);

            if (rhs.equalsIgnoreCase('null')) {
                if (op == '==') return leftVal == null;
                if (op == '!=') return leftVal != null;
                return false;
            }

            if (leftVal == null) return false;

            try {
                Decimal leftNum  = Decimal.valueOf(String.valueOf(leftVal));
                Decimal rightNum = Decimal.valueOf(rhs);
                if (op == '>')  return leftNum > rightNum;
                if (op == '<')  return leftNum < rightNum;
                if (op == '>=') return leftNum >= rightNum;
                if (op == '<=') return leftNum <= rightNum;
                if (op == '==') return leftNum == rightNum;
                if (op == '!=') return leftNum != rightNum;
            } catch (Exception e) { /* fall through to string comparison */ }

            String leftStr = String.valueOf(leftVal).trim();
            if (op == '==') return leftStr == rhs;
            if (op == '!=') return leftStr != rhs;
            return false;
        }
        throw new DocGen_Exception('Invalid expression: ' + expr);
    }

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
                // Static value types — TEXT/NUMBER/DATE are UI aliases for CONSTANT
                when 'CONSTANT', 'TEXT', 'NUMBER', 'DATE' {
                    resolved.put(v.variableName, v.staticValue != null ? v.staticValue : '');
                }
                when 'SYSTEM_DATE'  { resolved.put(v.variableName, Date.today().format()); }
                when 'CURRENT_USER' { resolved.put(v.variableName, UserInfo.getName()); }
                when 'ORG_NAME'     { resolved.put(v.variableName, UserInfo.getOrganizationName()); }
                when 'IMAGE'        { resolved.put(v.variableName, resolveImageToken(v.imageVersionId)); }
                // EXPRESSION and BOOLEAN are handled in resolveWithData; default here covers
                // EXPRESSION-type variables whose expression is a static string fallback
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
