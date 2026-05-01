public without sharing class DocGen_PdfController {

    public String content { get; private set; }

    public DocGen_PdfController() {
        String cvId = ApexPages.currentPage().getParameters().get('cvId');
        if (String.isNotBlank(cvId)) {
            List<ContentVersion> cvList = Database.queryWithBinds(
                'SELECT VersionData FROM ContentVersion WHERE Id = :cvId LIMIT 1',
                new Map<String, Object>{ 'cvId' => cvId },
                AccessLevel.SYSTEM_MODE
            );
            if (!cvList.isEmpty() && cvList[0].VersionData != null) {
                content = cvList[0].VersionData.toString();
            }
        }
        if (content == null) content = '<html><body><p>No content.</p></body></html>';
    }
}
