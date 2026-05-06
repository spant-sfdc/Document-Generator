public with sharing class DocGen_DocumentGeneratorService {

    public static String generateHtml(DocGen_Wrappers.TemplateConfigWrapper config) {
        if (config == null) throw new DocGen_Exception('Template config is required.');
        String templateHtml = DocGen_TemplateService.getTemplateText(config.templateId);

        // Auto-fill any tokens in the template that have no explicit mapping.
        // Existing explicit mappings are preserved unchanged and take priority.
        List<DocGen_Wrappers.TokenMappingWrapper> effectiveMappings =
            DocGen_SmartTokenResolver.mergeWithAutoResolved(
                config.primaryObject, templateHtml, config.tokenMappings);

        // Fetch record data using the merged (explicit + auto-resolved) mapping set
        DocGen_DataResolverService.ResolvedDataWrapper data =
            DocGen_DataResolverService.resolveData(
                config.recordId, config.primaryObject, effectiveMappings);

        // Build a token-aliased data map so BOOLEAN variable expressions can reference
        // token names (e.g. "total_amount > 1000") in addition to raw field API names.
        // Token names are the template placeholder names users define, which may differ
        // from field API names — without this alias map, evaluateExpression() would always
        // miss the lookup and treat the variable as false.
        Map<String, Object> tokenData = new Map<String, Object>(data.primaryRecord);
        for (DocGen_Wrappers.TokenMappingWrapper m : effectiveMappings) {
            if (m.mappingType != 'FIELD' || m.isRepeating == true || String.isBlank(m.token)) continue;
            String tokenName = m.token.replace('{{', '').replace('}}', '').trim();
            String fieldKey  = String.isNotBlank(m.relationshipPath) ? m.relationshipPath : m.sourceField;
            if (String.isNotBlank(fieldKey) && !tokenData.containsKey(tokenName)) {
                Object val = data.primaryRecord.get(fieldKey);
                if (val != null) tokenData.put(tokenName, val);
            }
        }

        // Resolve variables with live record data so EXPRESSION-type variables work
        Map<String, String> variables =
            DocGen_VariableResolverService.resolveWithData(config.variables, tokenData);

        return DocGen_MergeEngineService.mergeTemplate(
            templateHtml, data.primaryRecord, data.childRecords, variables, effectiveMappings);
    }

    /**
     * Generates merged HTML and injects print styles in a single call.
     * Used by storeMergedHtml() in DocGen_Controller to produce the styled
     * HTML that is stored as a temp ContentVersion before PDF rendering.
     */
    public static String getStyledHtml(DocGen_Wrappers.TemplateConfigWrapper config) {
        return injectPrintStyles(generateHtml(config));
    }

    /**
     * Generates a PDF by passing a committed ContentVersion ID as a tiny
     * URL parameter to the DocGen_PdfRenderer VF page.
     *
     * The ContentVersion must have been inserted (and committed) in a prior
     * @AuraEnabled call. getContentAsPDF() fires a separate internal HTTP
     * request — DML in the current transaction is not yet committed, making
     * a same-transaction ContentVersion invisible to the VF controller.
     * Splitting into two transactions (storeMergedHtml → generatePdfFromCv)
     * solves this without relying on Platform Cache.
     */
    public static Blob generatePdfFromCv(String cvId) {
        if (String.isBlank(cvId)) {
            throw new DocGen_Exception('generatePdfFromCv: cvId is required');
        }
        System.debug(LoggingLevel.INFO,
            'DocGen_DocumentGeneratorService.generatePdfFromCv: cvId=' + cvId);
        PageReference pr = new PageReference('/apex/DocGen_PdfRenderer');
        pr.getParameters().put('cvId', cvId);

        if (Test.isRunningTest()) {
            return Blob.valueOf('PDF_PLACEHOLDER');
        }
        Blob pdfBlob = pr.getContentAsPDF();
        System.debug(LoggingLevel.INFO,
            'DocGen_DocumentGeneratorService.generatePdfFromCv: pdfBlob size='
            + (pdfBlob != null ? pdfBlob.size() : -1));
        return pdfBlob;
    }

    private static String injectPrintStyles(String html) {
        String css = '<style>'
            + 'body{font-family:Arial,sans-serif;font-size:11pt;margin:20px;}'
            + 'table{width:100%;border-collapse:collapse;margin-bottom:10px;}'
            + 'td,th{border:1px solid #ccc;padding:6px;text-align:left;}'
            + 'th{background:#f0f0f0;font-weight:bold;}'
            + 'h1,h2,h3{margin-bottom:8px;}'
            + '</style>';
        if (String.isNotBlank(html) && html.contains('<head>')) {
            return html.replace('<head>', '<head>' + css);
        }
        return css + (html != null ? html : '');
    }
}
