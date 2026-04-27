public class DocGen_MergeEngineService {

    public static String mergeTemplate(
        String templateHtml,
        Map<String, Object> primaryData,
        Map<String, List<Map<String, Object>>> childData,
        Map<String, String> resolvedVariables,
        List<DocGen_Wrappers.TokenMappingWrapper> mappings
    ) {
        if (String.isBlank(templateHtml)) return '';
        String result = templateHtml;

        if (resolvedVariables != null) {
            for (String varToken : resolvedVariables.keySet()) {
                String safeVal = resolvedVariables.get(varToken) != null
                    ? resolvedVariables.get(varToken) : '';
                result = result.replace('{{' + varToken + '}}', safeVal);
                result = result.replace('{{sys.' + varToken + '}}', safeVal);
            }
        }

        result = processRepeatingSections(result, childData, mappings);
        result = processConditionals(result, primaryData, mappings);

        if (mappings != null) {
            for (DocGen_Wrappers.TokenMappingWrapper m : mappings) {
                if (m.isRepeating == true) continue;
                String rawValue = extractValueFromData(primaryData, m);
                String formatted = applyFormat(rawValue, m.formatOverride);
                if (String.isNotBlank(m.token)) {
                    result = result.replace(m.token, formatted);
                }
            }
        }
        return result;
    }

    private static String processRepeatingSections(
        String html,
        Map<String, List<Map<String, Object>>> childData,
        List<DocGen_Wrappers.TokenMappingWrapper> mappings
    ) {
        if (String.isBlank(html)) return html;
        Pattern secPattern = Pattern.compile(
            '\\{\\{#([a-zA-Z0-9_]+)\\}\\}([\\s\\S]*?)\\{\\{/\\1\\}\\}'
        );
        Matcher m = secPattern.matcher(html);
        String result = html;
        List<String[]> replacements = new List<String[]>();

        while (m.find()) {
            String sectionName = m.group(1);
            String rowTemplate = m.group(2);
            String fullMatch   = m.group(0);
            String expanded    = '';

            if (childData != null && childData.containsKey(sectionName)) {
                List<Map<String, Object>> rows = childData.get(sectionName);
                List<DocGen_Wrappers.TokenMappingWrapper> sectionMappings =
                    getSectionMappings(mappings, sectionName);
                for (Map<String, Object> row : rows) {
                    String rowHtml = rowTemplate;
                    for (DocGen_Wrappers.TokenMappingWrapper sm : sectionMappings) {
                        if (String.isBlank(sm.token)) continue;
                        Object rawObj = row.get(sm.sourceField);
                        String val = rawObj != null ? String.valueOf(rawObj) : '';
                        rowHtml = rowHtml.replace(sm.token, applyFormat(val, sm.formatOverride));
                    }
                    expanded += rowHtml;
                }
            }
            replacements.add(new String[]{ fullMatch, expanded });
        }

        for (String[] pair : replacements) {
            result = result.replace(pair[0], pair[1]);
        }
        return result;
    }

    private static String processConditionals(
        String html,
        Map<String, Object> data,
        List<DocGen_Wrappers.TokenMappingWrapper> mappings
    ) {
        if (String.isBlank(html)) return html;
        Pattern ifPattern = Pattern.compile(
            '\\{\\{#if ([a-zA-Z0-9_.]+)\\}\\}([\\s\\S]*?)\\{\\{/if\\}\\}'
        );
        Matcher m = ifPattern.matcher(html);
        String result = html;
        List<String[]> replacements = new List<String[]>();

        while (m.find()) {
            String condField = m.group(1);
            String block     = m.group(2);
            String fullMatch = m.group(0);
            Object condVal   = data != null ? data.get(condField) : null;
            String replacement = isTruthy(condVal) ? block : '';
            replacements.add(new String[]{ fullMatch, replacement });
        }

        for (String[] pair : replacements) {
            result = result.replace(pair[0], pair[1]);
        }
        return result;
    }

    private static String extractValueFromData(
        Map<String, Object> data,
        DocGen_Wrappers.TokenMappingWrapper mapping
    ) {
        if (mapping == null) return '';
        if (mapping.mappingType == 'CONSTANT') return mapping.staticValue != null ? mapping.staticValue : '';
        if (data == null) return '';
        String fieldKey = String.isNotBlank(mapping.relationshipPath)
            ? mapping.relationshipPath : mapping.sourceField;
        Object val = data.get(fieldKey);
        return val != null ? String.valueOf(val) : '';
    }

    public static String applyFormat(String rawValue, String formatOverride) {
        if (String.isBlank(rawValue)) return rawValue != null ? rawValue : '';
        if (String.isBlank(formatOverride)) return rawValue;
        String[] parts = formatOverride.split(':');
        String fType   = parts[0].trim().toLowerCase();
        String fParam  = parts.size() > 1 ? parts[1].trim() : '';

        if (fType == 'date') {
            try {
                Date d = Date.valueOf(rawValue);
                String fmt = String.isNotBlank(fParam) ? fParam : 'MM/dd/yyyy';
                return Datetime.newInstance(d, Time.newInstance(0,0,0,0)).format(fmt);
            } catch (Exception e) { return rawValue; }
        }
        if (fType == 'currency') {
            try { return '$' + Decimal.valueOf(rawValue).setScale(2).toPlainString(); }
            catch (Exception e) { return rawValue; }
        }
        if (fType == 'number') {
            try {
                Integer scale = String.isNotBlank(fParam) ? Integer.valueOf(fParam) : 2;
                return Decimal.valueOf(rawValue).setScale(scale).toPlainString();
            } catch (Exception e) { return rawValue; }
        }
        if (fType == 'upper') return rawValue.toUpperCase();
        if (fType == 'lower') return rawValue.toLowerCase();
        return rawValue;
    }

    private static Boolean isTruthy(Object val) {
        if (val == null) return false;
        if (val instanceof Boolean) return (Boolean)val;
        String s = String.valueOf(val).toLowerCase().trim();
        return s != 'false' && s != '0' && s != '' && s != 'null';
    }

    private static List<DocGen_Wrappers.TokenMappingWrapper> getSectionMappings(
        List<DocGen_Wrappers.TokenMappingWrapper> all, String sectionName
    ) {
        List<DocGen_Wrappers.TokenMappingWrapper> result = new List<DocGen_Wrappers.TokenMappingWrapper>();
        if (all == null) return result;
        for (DocGen_Wrappers.TokenMappingWrapper m : all) {
            if (m.isRepeating == true && m.repeatObject == sectionName) result.add(m);
        }
        return result;
    }
}
