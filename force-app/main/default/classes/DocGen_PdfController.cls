public without sharing class DocGen_PdfController {

    public String content { get; private set; }

    public DocGen_PdfController() {
        String cvId = ApexPages.currentPage().getParameters().get('cvId');
        System.debug(LoggingLevel.INFO, 'DocGen_PdfController: cvId=' + cvId);
        if (String.isNotBlank(cvId)) {
            List<ContentVersion> cvList = Database.queryWithBinds(
                'SELECT VersionData, ContentSize FROM ContentVersion WHERE Id = :cvId LIMIT 1',
                new Map<String, Object>{ 'cvId' => cvId },
                AccessLevel.SYSTEM_MODE
            );
            System.debug(LoggingLevel.INFO,
                'DocGen_PdfController: found=' + !cvList.isEmpty()
                + ' vdNull=' + (cvList.isEmpty() ? 'n/a' : String.valueOf(cvList[0].VersionData == null))
                + ' size=' + (cvList.isEmpty() ? 'n/a' : String.valueOf(cvList[0].ContentSize)));
            if (!cvList.isEmpty() && cvList[0].VersionData != null) {
                content = cvList[0].VersionData.toString();
                System.debug(LoggingLevel.INFO,
                    'DocGen_PdfController: content length=' + content.length());
            }
        }
        if (content == null) {
            System.debug(LoggingLevel.WARN, 'DocGen_PdfController: content is null — falling back');
            content = '<html><body><p>No content.</p></body></html>';
        }
    }
}
