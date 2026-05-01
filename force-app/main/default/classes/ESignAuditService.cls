/**
 * Insert-only audit trail engine for SF-eSign.
 *
 * IMMUTABILITY CONTRACT:
 *  - This class only ever calls `insert` on Signature_Audit__c.
 *  - Updates and deletes on Signature_Audit__c are blocked by
 *    ESignAuditTrigger (Phase 7) as a second enforcement layer.
 *  - Tokens are masked via ESignTokenService.maskToken() before storage.
 *
 * All methods are intentionally fire-and-forget with their own
 * try/catch so an audit failure never rolls back a business transaction.
 */
public class ESignAuditService {

    // ─────────────────────────────────────────────────────────────────────────
    // PRIMARY LOG METHOD
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Logs a single audit event.
     *
     * @param requestId   Signature_Request__c Id (may be null for pre-insert errors)
     * @param eventType   Picklist value from Signature_Audit__c.Event_Type__c
     * @param actorEmail  Email of the person/system acting
     * @param rawToken    Full token — will be masked before insert
     * @param ip          Client IP (nullable)
     * @param userAgent   Browser UA string (nullable)
     * @param sourceSystem Caller identifier (e.g. 'DocGen', 'Site', 'Scheduler')
     */
    public static void log(
            String requestId,
            String eventType,
            String actorEmail,
            String rawToken,
            String ip,
            String userAgent,
            String sourceSystem) {

        try {
            Database.insert(
                buildAuditRecord(requestId, eventType, actorEmail,
                    rawToken, ip, userAgent, sourceSystem, null),
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception e) {
            // Swallow — audit must not break the calling transaction.
            // Unhandled audit failures are visible in debug logs.
            System.debug(LoggingLevel.ERROR,
                'ESignAuditService.log failed for event ' + eventType + ': ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ERROR LOG METHOD
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Convenience method for Error events with a detail payload.
     */
    public static void logError(
            String requestId,
            String errorDetail,
            String actorEmail,
            String rawToken,
            String sourceSystem) {

        // Signature_Audit__c.Signature_Request__c is Master-Detail (required).
        // Inserting with a null parent throws a DML exception. Skip insert and
        // write to debug log instead — the error is still visible in Setup → Debug Logs.
        if (String.isBlank(requestId)) {
            System.debug(LoggingLevel.ERROR,
                'ESignAuditService.logError [no requestId] source=' + sourceSystem
                + ' token=' + ESignTokenService.maskToken(rawToken)
                + ' detail=' + errorDetail);
            return;
        }

        try {
            Signature_Audit__c rec = buildAuditRecord(
                requestId, 'Error', actorEmail,
                rawToken, null, null, sourceSystem, errorDetail
            );
            Database.insert(rec, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'ESignAuditService.logError failed: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RATE-LIMIT LOG METHOD
    // ─────────────────────────────────────────────────────────────────────────

    public static void logRateLimit(
            String requestId,
            String actorEmail,
            String rawToken,
            String ip,
            Integer loadCount) {

        try {
            Database.insert(
                buildAuditRecord(requestId, 'Rate_Limited', actorEmail,
                    rawToken, ip, null, 'Site',
                    JSON.serialize(new Map<String, Object>{
                        'loadCount' => loadCount,
                        'threshold' => Integer.valueOf(System.Label.ESign_Rate_Limit_Per_Hour)
                    })),
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'ESignAuditService.logRateLimit failed: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // BULK LOG (for scheduler)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Bulk-logs a list of events in one DML call.
     * Used by ESignExpiryScheduler to avoid per-record DML.
     */
    public static void logBulk(List<Signature_Audit__c> events) {
        if (events == null || events.isEmpty()) return;
        try {
            Database.insert(events, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'ESignAuditService.logBulk failed: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INTERNAL BUILDER
    // ─────────────────────────────────────────────────────────────────────────

    private static Signature_Audit__c buildAuditRecord(
            String requestId,
            String eventType,
            String actorEmail,
            String rawToken,
            String ip,
            String userAgent,
            String sourceSystem,
            String detail) {

        return new Signature_Audit__c(
            Signature_Request__c = requestId,
            Event_Type__c        = eventType,
            Event_Timestamp__c   = DateTime.now(),
            Actor_Email__c       = actorEmail,
            Token__c             = ESignTokenService.maskToken(rawToken),
            IP_Address__c        = ip,
            User_Agent__c        = (userAgent != null && userAgent.length() > 255)
                                        ? userAgent.substring(0, 255)
                                        : userAgent,
            Source_System__c     = sourceSystem,
            Event_Detail__c      = detail
        );
    }
}
