public with sharing class DocGen_DocumentGeneratorService {

    public static String generateHtml(DocGen_Wrappers.TemplateConfigWrapper config) {
        if (config == null) throw new DocGen_Exception('Template config is required.');
        String templateHtml = DocGen_TemplateService.getTemplateText(config.templateId);
        Map<String, String> variables = DocGen_VariableResolverService.resolve(config.variables);
        DocGen_DataResolverService.ResolvedDataWrapper data =
            DocGen_DataResolverService.resolveData(
                config.recordId,
                config.primaryObject,
                config.tokenMappings
            );
        return DocGen_MergeEngineService.mergeTemplate(
            templateHtml,
            data.primaryRecord,
            data.childRecords,
            variables,
            config.tokenMappings
        );
    }

    public static Blob generatePdf(String mergedHtml) {
        if (String.isBlank(mergedHtml)) {
            throw new DocGen_Exception('generatePdf: mergedHtml is blank — cannot produce PDF');
        }
        String styledHtml = injectPrintStyles(mergedHtml);
        System.debug(LoggingLevel.INFO,
            'DocGen_DocumentGeneratorService.generatePdf: styledHtml length=' + styledHtml.length());

        // Pass HTML directly to the VF page via base64 URL parameter.
        // This avoids the cross-transaction visibility problem where a temp
        // ContentVersion inserted here would not be visible inside the
        // separate execution context that getContentAsPDF() creates.
        String encodedHtml = EncodingUtil.base64Encode(Blob.valueOf(styledHtml));
        PageReference pr = new PageReference('/apex/DocGen_PdfRenderer');
        pr.getParameters().put('html', encodedHtml);

        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('PDF_PLACEHOLDER');
        } else {
            pdfBlob = pr.getContentAsPDF();
        }
        System.debug(LoggingLevel.INFO,
            'DocGen_DocumentGeneratorService.generatePdf: pdfBlob size='
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
