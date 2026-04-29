public without sharing class DocGen_HtmlViewerController {
    public String htmlContent { get; private set; }

    public DocGen_HtmlViewerController() {
        String cvId = ApexPages.currentPage().getParameters().get('cvId');
        if (String.isBlank(cvId)) {
            htmlContent = '<p>No preview content found.</p>';
            return;
        }
        try {
            ContentVersion cv = [
                SELECT VersionData FROM ContentVersion WHERE Id = :cvId LIMIT 1
            ];
            htmlContent = extractBodyContent(cv.VersionData.toString());
        } catch (Exception e) {
            htmlContent = '<p>Error loading preview: ' + e.getMessage() + '</p>';
        }
    }

    // Pulls <style> blocks and <body> inner content out of a full HTML document.
    // VF already provides the outer html/head/body wrapper via its own page render;
    // injecting a second full document causes the browser to drop the inner <head>
    // (HTML5 spec: "head" start tag in "in body" mode = parse error, ignore), which
    // silently discards the template CSS and collapses the layout.
    private static String extractBodyContent(String html) {
        if (String.isBlank(html)) return '';

        String styles = '';
        Matcher sm = Pattern.compile('<style[^>]*>[\\s\\S]*?</style>').matcher(html);
        while (sm.find()) styles += sm.group(0) + '\n';

        // Greedy match grabs everything between first <body...> and last </body>
        String body = html;
        Matcher bm = Pattern.compile('<body[^>]*>([\\s\\S]*)</body>').matcher(html);
        if (bm.find()) body = bm.group(1);

        return styles + body;
    }
}
