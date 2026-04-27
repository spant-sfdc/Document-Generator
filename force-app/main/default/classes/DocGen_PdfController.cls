public with sharing class DocGen_PdfController {

    public String content { get; private set; }

    public DocGen_PdfController() {
        String cvId = ApexPages.currentPage().getParameters().get('cvId');
        if (String.isNotBlank(cvId)) {
            List<ContentVersion> cvList = [
                SELECT VersionData FROM ContentVersion
                WHERE Id = :cvId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!cvList.isEmpty()) {
                content = cvList[0].VersionData.toString();
            }
        }
        if (content == null) content = '<html><body><p>No content.</p></body></html>';
    }
}
