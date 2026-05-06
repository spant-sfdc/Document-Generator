public without sharing class DocGen_PdfController {

    public String content { get; private set; }

    public DocGen_PdfController() {
        Map<String, String> params = ApexPages.currentPage().getParameters();

        String cvId = params.get('cvId');
        if (String.isNotBlank(cvId)) {
            try {
                List<ContentVersion> cvs = Database.queryWithBinds(
                    'SELECT VersionData FROM ContentVersion WHERE Id = :cvId LIMIT 1',
                    new Map<String, Object>{ 'cvId' => cvId },
                    AccessLevel.SYSTEM_MODE
                );
                if (!cvs.isEmpty() && cvs[0].VersionData != null) {
                    content = sanitizeForPdf(cvs[0].VersionData.toString());
                    System.debug(LoggingLevel.INFO,
                        'DocGen_PdfController: loaded from ContentVersion. length=' + content.length());
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'DocGen_PdfController: ContentVersion query failed: ' + e.getMessage());
            }
        }

        if (content == null) {
            System.debug(LoggingLevel.WARN, 'DocGen_PdfController: content is null — no valid cvId');
            content = '<html><body><p style="font-family:Arial,sans-serif;padding:20px;">Document content unavailable.</p></body></html>';
        }
    }

    private static String sanitizeForPdf(String html) {
        if (String.isBlank(html)) return null;
        // Remove script blocks — PDF engine does not support JS
        html = html.replaceAll('(?i)<script[\\s\\S]*?</script>', '');
        // Remove external stylesheet links — PDF engine cannot fetch external resources
        html = html.replaceAll('(?i)<link[^>]*/>', '');
        html = html.replaceAll('(?i)<link[^>]*>', '');
        // Remove @import rules
        html = html.replaceAll('(?i)@import[^;]+;', '');
        // Replace flex layout (unsupported by VF PDF engine) with block
        html = html.replace('display: flex', 'display:block');
        html = html.replace('display:flex', 'display:block');
        // Replace position:fixed (unsupported — causes layout crash)
        html = html.replace('position: fixed', 'position:static');
        html = html.replace('position:fixed', 'position:static');
        // Ensure content is wrapped in a valid HTML document
        if (!html.toLowerCase().contains('<html')) {
            html = '<html><body>' + html + '</body></html>';
        }
        return html;
    }
}
