public without sharing class DocGen_PdfController {

    public String content { get; private set; }

    public DocGen_PdfController() {
        String encodedHtml = ApexPages.currentPage().getParameters().get('html');
        System.debug(LoggingLevel.INFO,
            'DocGen_PdfController: html param length=' + (encodedHtml != null ? encodedHtml.length() : 0));
        if (String.isNotBlank(encodedHtml)) {
            try {
                content = EncodingUtil.base64Decode(encodedHtml).toString();
                System.debug(LoggingLevel.INFO,
                    'DocGen_PdfController: decoded content length=' + content.length());
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'DocGen_PdfController: base64 decode failed: ' + e.getMessage());
            }
        }
        if (content == null) {
            System.debug(LoggingLevel.WARN, 'DocGen_PdfController: content is null — falling back');
            content = '<html><body><p>No content.</p></body></html>';
        }
    }
}
