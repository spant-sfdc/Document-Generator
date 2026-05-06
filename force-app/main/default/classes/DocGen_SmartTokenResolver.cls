public with sharing class DocGen_SmartTokenResolver {

    // ── Public API ─────────────────────────────────────────────────────────────

    /**
     * Merges explicit tokenMappings with auto-resolved ones for any token in
     * templateHtml that has no existing explicit mapping.
     * Existing mappings take priority and are returned unchanged.
     */
    public static List<DocGen_Wrappers.TokenMappingWrapper> mergeWithAutoResolved(
        String primaryObject,
        String templateHtml,
        List<DocGen_Wrappers.TokenMappingWrapper> explicitMappings
    ) {
        if (String.isBlank(primaryObject) || String.isBlank(templateHtml)) {
            return explicitMappings != null
                ? explicitMappings
                : new List<DocGen_Wrappers.TokenMappingWrapper>();
        }

        // Build context-aware skip keys from existing explicit mappings
        Set<String> coveredKeys = new Set<String>();
        List<DocGen_Wrappers.TokenMappingWrapper> result =
            explicitMappings != null
                ? new List<DocGen_Wrappers.TokenMappingWrapper>(explicitMappings)
                : new List<DocGen_Wrappers.TokenMappingWrapper>();

        for (DocGen_Wrappers.TokenMappingWrapper m : result) {
            if (String.isBlank(m.token)) continue;
            String ctx = (m.isRepeating == true && String.isNotBlank(m.repeatObject))
                ? m.repeatObject : '__primary__';
            coveredKeys.add(ctx + '|' + m.token.trim());
        }

        List<DocGen_Wrappers.TokenMappingWrapper> autoMappings =
            resolve(primaryObject, templateHtml, coveredKeys);
        result.addAll(autoMappings);
        return result;
    }

    /**
     * Auto-resolves all tokens in templateHtml for primaryObject.
     * skipKeys uses the format "repeatObject|{{token}}" or "__primary__|{{token}}".
     * Throws DocGen_Exception for tokens that cannot be resolved.
     */
    public static List<DocGen_Wrappers.TokenMappingWrapper> resolve(
        String primaryObject,
        String templateHtml,
        Set<String> skipKeys
    ) {
        DocGen_SchemaService.validateObjectName(primaryObject);
        ObjSchema sch         = buildSchema(primaryObject);
        List<ParsedToken> tokens = parseTokens(templateHtml);

        List<DocGen_Wrappers.TokenMappingWrapper> mappings = new List<DocGen_Wrappers.TokenMappingWrapper>();
        Set<String> generatedKeys = new Set<String>();

        for (ParsedToken pt : tokens) {
            String rawToken = '{{' + pt.tokenContent + '}}';

            // Resolve the child SObject API name for this context (if inside a section)
            String childSObjectName = null;
            if (pt.sectionContext != null) {
                childSObjectName = sch.childRelNameToObj.get(pt.sectionContext.toLowerCase());
            }

            // Context key: distinguishes {{Name}} at primary level vs inside a child section
            String ctxPrefix = (childSObjectName != null) ? childSObjectName : '__primary__';
            String contextKey = ctxPrefix + '|' + rawToken;

            if (skipKeys != null && skipKeys.contains(contextKey)) continue;
            if (generatedKeys.contains(contextKey)) continue;
            generatedKeys.add(contextKey);

            DocGen_Wrappers.TokenMappingWrapper m = resolveToken(pt, sch, primaryObject);
            if (m != null) mappings.add(m);
        }
        return mappings;
    }

    // ── Schema model ───────────────────────────────────────────────────────────

    private class ObjSchema {
        String primaryObject;
        Map<String, String> primaryFieldMap;             // lowercase field name -> API field name
        Map<String, String> relNameToRefObject;          // lowercase rel name -> referenced object API name
        Map<String, String> childRelNameToObj;           // lowercase child rel name -> child SObject API name
        Map<String, Map<String, String>> childFieldMaps; // child SObject API name -> (lowercase -> API field)

        ObjSchema() {
            primaryFieldMap    = new Map<String, String>();
            relNameToRefObject = new Map<String, String>();
            childRelNameToObj  = new Map<String, String>();
            childFieldMaps     = new Map<String, Map<String, String>>();
        }
    }

    private static ObjSchema buildSchema(String primaryObject) {
        ObjSchema s = new ObjSchema();
        s.primaryObject = primaryObject;

        Schema.DescribeSObjectResult dr =
            Schema.getGlobalDescribe().get(primaryObject)?.getDescribe();
        if (dr == null) throw new DocGen_Exception('Unknown object: ' + primaryObject);

        // Primary fields and parent relationship names
        for (Schema.SObjectField f : dr.fields.getMap().values()) {
            Schema.DescribeFieldResult dfr = f.getDescribe();
            if (!dfr.isAccessible()) continue;
            s.primaryFieldMap.put(dfr.getName().toLowerCase(), dfr.getName());
            if (dfr.getType() == Schema.DisplayType.REFERENCE) {
                String relName = dfr.getRelationshipName();
                if (String.isNotBlank(relName)) {
                    List<Schema.SObjectType> refs = dfr.getReferenceTo();
                    if (!refs.isEmpty()) {
                        s.relNameToRefObject.put(relName.toLowerCase(), refs[0].getDescribe().getName());
                    }
                }
            }
        }

        // Child relationships — pre-load field maps for all queryable children
        for (Schema.ChildRelationship cr : dr.getChildRelationships()) {
            String relName = cr.getRelationshipName();
            if (String.isBlank(relName)) continue;
            Schema.DescribeSObjectResult childDr = cr.getChildSObject().getDescribe();
            if (!childDr.isQueryable() || !childDr.isAccessible()) continue;
            String childObj = childDr.getName();
            s.childRelNameToObj.put(relName.toLowerCase(), childObj);
            if (!s.childFieldMaps.containsKey(childObj)) {
                Map<String, String> cfm = new Map<String, String>();
                for (Schema.SObjectField cf : childDr.fields.getMap().values()) {
                    Schema.DescribeFieldResult cdfr = cf.getDescribe();
                    if (cdfr.isAccessible()) cfm.put(cdfr.getName().toLowerCase(), cdfr.getName());
                }
                s.childFieldMaps.put(childObj, cfm);
            }
        }
        return s;
    }

    // ── Token parsing ──────────────────────────────────────────────────────────

    private class ParsedToken {
        String tokenContent;           // raw content between {{ }}, e.g. '#OpportunityLineItems', 'Account.Name'
        String sectionContext;  // null for primary/parent tokens; relationship name when inside a child block
        Boolean isSection;      // true for {{#sectionName}} open markers
    }

    private static List<ParsedToken> parseTokens(String html) {
        List<ParsedToken> result = new List<ParsedToken>();
        Pattern p = Pattern.compile('\\{\\{([^{}]+)\\}\\}');
        Matcher m = p.matcher(html);
        List<String> sectionStack = new List<String>(); // stack of section/relationship names

        while (m.find()) {
            String tokenContent = m.group(1).trim();

            // sys.* tokens are handled by VariableResolverService — skip entirely
            if (tokenContent.startsWith('sys.')) continue;

            // Closing tag: pop matching entry from stack, don't emit token
            if (tokenContent.startsWith('/')) {
                String closingName = tokenContent.substring(1).trim();
                if (!sectionStack.isEmpty()
                    && sectionStack[sectionStack.size() - 1] == closingName) {
                    sectionStack.remove(sectionStack.size() - 1);
                }
                continue;
            }

            ParsedToken pt    = new ParsedToken();
            pt.tokenContent          = tokenContent;
            pt.isSection      = tokenContent.startsWith('#');
            pt.sectionContext = sectionStack.isEmpty() ? null : sectionStack[sectionStack.size() - 1];

            if (pt.isSection) {
                String secName = tokenContent.substring(1).trim();
                // Push only real section names — {{#if ...}} directives don't create child context
                if (!secName.startsWith('if ') && secName != 'if') {
                    sectionStack.add(secName);
                }
            }

            result.add(pt);
        }
        return result;
    }

    // ── Resolution dispatch ────────────────────────────────────────────────────

    private static DocGen_Wrappers.TokenMappingWrapper resolveToken(
        ParsedToken pt,
        ObjSchema sch,
        String primaryObject
    ) {
        String tokenContent = pt.tokenContent;

        // Conditional directives — resolved by VariableResolverService, no field mapping needed
        if (tokenContent.startsWith('#if ') || tokenContent == '#if' || tokenContent.startsWith('if ')) {
            return null;
        }

        // Child section open: {{#OpportunityLineItems}}
        if (pt.isSection) {
            return resolveChildSection(tokenContent.substring(1).trim(), sch, primaryObject);
        }

        // Inside a repeating section — resolve against child object fields
        if (pt.sectionContext != null) {
            return resolveChildField(tokenContent, pt.sectionContext, sch, primaryObject);
        }

        // Parent traversal: {{Account.Name}} or {{Owner.Name}}
        if (tokenContent.contains('.')) {
            return resolveParentTraversal(tokenContent, sch, primaryObject);
        }

        // Direct primary object field: {{Name}}, {{StageName}}
        return resolvePrimaryField(tokenContent, sch, primaryObject);
    }

    private static DocGen_Wrappers.TokenMappingWrapper resolvePrimaryField(
        String tokenName,
        ObjSchema sch,
        String primaryObject
    ) {
        String apiField = sch.primaryFieldMap.get(tokenName.toLowerCase());
        if (apiField == null) return null; // custom token — explicit mapping required, skip auto-resolve
        DocGen_Wrappers.TokenMappingWrapper m = new DocGen_Wrappers.TokenMappingWrapper();
        m.token        = '{{' + tokenName + '}}';
        m.sourceObject = primaryObject;
        m.sourceField  = apiField;
        m.mappingType  = 'FIELD';
        m.isRepeating  = false;
        return m;
    }

    private static DocGen_Wrappers.TokenMappingWrapper resolveParentTraversal(
        String tokenName,
        ObjSchema sch,
        String primaryObject
    ) {
        String[] parts   = tokenName.split('\\.');
        String relName   = parts[0];
        String refObject = sch.relNameToRefObject.get(relName.toLowerCase());

        if (refObject == null) return null; // unknown relationship — skip auto-resolve

        // Normalise the traversal path and validate the final field (single-hop)
        String traversalPath = tokenName;
        if (parts.size() == 2) {
            Schema.DescribeSObjectResult refDr =
                Schema.getGlobalDescribe().get(refObject)?.getDescribe();
            if (refDr != null) {
                String finalField = parts[1];
                Schema.DescribeFieldResult dfr =
                    refDr.fields.getMap().get(finalField.toLowerCase())?.getDescribe();
                if (dfr == null || !dfr.isAccessible()) return null; // unknown field — skip
                traversalPath = relName + '.' + dfr.getName();
            }
        }

        DocGen_Wrappers.TokenMappingWrapper m = new DocGen_Wrappers.TokenMappingWrapper();
        m.token            = '{{' + tokenName + '}}';
        m.sourceObject     = primaryObject;
        m.sourceField      = parts[parts.size() - 1];
        m.relationshipPath = traversalPath;
        m.mappingType      = 'FIELD';
        m.isRepeating      = false;
        return m;
    }

    private static DocGen_Wrappers.TokenMappingWrapper resolveChildSection(
        String sectionName,
        ObjSchema sch,
        String primaryObject
    ) {
        String childObj = sch.childRelNameToObj.get(sectionName.toLowerCase());
        if (childObj == null) return null; // unknown child relationship — skip auto-resolve
        DocGen_Wrappers.TokenMappingWrapper m = new DocGen_Wrappers.TokenMappingWrapper();
        m.token        = '{{#' + sectionName + '}}';
        m.sourceObject = childObj;
        m.repeatObject = childObj;  // child SObject API name — used by DataResolverService for SOQL
        m.mappingType  = 'FIELD';
        m.isRepeating  = true;
        return m;
    }

    private static DocGen_Wrappers.TokenMappingWrapper resolveChildField(
        String tokenName,
        String sectionName,   // relationship name used in the template (e.g. "OpportunityLineItems")
        ObjSchema sch,
        String primaryObject
    ) {
        String childObj = sch.childRelNameToObj.get(sectionName.toLowerCase());
        if (childObj == null) return null; // unknown section context — skip
        Map<String, String> cfm = sch.childFieldMaps.get(childObj);
        if (cfm == null) return null; // schema not loaded — skip
        String apiField = cfm.get(tokenName.toLowerCase());
        if (apiField == null) return null; // custom token inside section — skip auto-resolve
        DocGen_Wrappers.TokenMappingWrapper m = new DocGen_Wrappers.TokenMappingWrapper();
        m.token        = '{{' + tokenName + '}}';
        m.sourceObject = childObj;
        m.sourceField  = apiField;
        m.repeatObject = childObj;  // groups this mapping under the right child section
        m.mappingType  = 'FIELD';
        m.isRepeating  = true;
        return m;
    }
}
