/**
 * PlatformEventLogController
 *
 * Apex controller for the Platform Event Monitoring LWC components.
 * Handles creation and retrieval of Platform_Event_Log__c records.
 *
 * Record Type routing:
 *   - "Standard Platform Event" → Standard_Platform_Event RT
 *   - "Change Data Capture"     → Change_Data_Capture RT
 *   - "Custom Platform Event"   → Custom_Platform_Event RT
 */
public with sharing class PlatformEventLogController {

    // ──────────────────────────────────────────────────────────────────────────
    // Record type developer name constants
    // ──────────────────────────────────────────────────────────────────────────
    private static final String RT_STANDARD = 'Standard_Platform_Event';
    private static final String RT_CDC      = 'Change_Data_Capture';
    private static final String RT_CUSTOM   = 'Custom_Platform_Event';

    // ──────────────────────────────────────────────────────────────────────────
    // Lazy-loaded record type ID map
    // ──────────────────────────────────────────────────────────────────────────
    @TestVisible private static Map<String, Id> recordTypeCache;

    private static Map<String, Id> getRecordTypeMap() {
        if (recordTypeCache == null) {
            recordTypeCache = new Map<String, Id>();
            for (RecordType rt : [
                SELECT Id, DeveloperName
                FROM RecordType
                WHERE SObjectType = 'Platform_Event_Log__c'
                WITH SECURITY_ENFORCED
            ]) {
                recordTypeCache.put(rt.DeveloperName, rt.Id);
            }
        }
        return recordTypeCache;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Expose record type IDs to LWC
    // ──────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getRecordTypeIds() {
        Map<String, String> result = new Map<String, String>();
        for (String devName : getRecordTypeMap().keySet()) {
            result.put(devName, getRecordTypeMap().get(devName));
        }
        return result;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Create a Platform_Event_Log__c record from data received by EMP API
    // ──────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static Id createEventLog(
        String eventApiName,
        String eventType,
        String channel,
        String payload,
        String headerData,
        String replayId,
        String publishedById,
        String publishedDate,
        String schemaId,
        String entityName,
        String changeType,
        String changedFields,
        String commitTimestamp
    ) {
        Platform_Event_Log__c log = new Platform_Event_Log__c();

        // Core fields
        log.Event_API_Name__c       = truncate(eventApiName, 255);
        log.Event_Type__c           = eventType;
        log.Channel__c              = truncate(channel, 255);
        log.Replay_ID__c            = truncate(replayId, 50);
        log.Published_By_ID__c      = truncate(publishedById, 255);
        log.Schema_ID__c            = truncate(schemaId, 255);
        log.Payload__c              = payload;
        log.Header_Data__c          = headerData;
        log.Subscription_Status__c  = 'Received';
        log.Event_UUID__c           = generateUUID();

        // CDC-specific fields
        log.Entity_Name__c   = truncate(entityName, 255);
        log.Change_Type__c   = changeType;
        log.Changed_Fields__c = changedFields;
        if (String.isNotBlank(commitTimestamp)) {
            try {
                log.Commit_Timestamp__c = Long.valueOf(commitTimestamp);
            } catch (Exception e) { /* ignore */ }
        }

        // Parse published date
        if (String.isNotBlank(publishedDate)) {
            try {
                String normalized = publishedDate
                    .replace('T', ' ')
                    .replace('Z', '')
                    .left(19);
                log.Event_Published_Date__c = (DateTime) DateTime.valueOf(normalized);
            } catch (Exception e) { /* ignore */ }
        }

        // Assign record type
        Map<String, Id> rtMap = getRecordTypeMap();
        if ('Standard Platform Event'.equals(eventType) && rtMap.containsKey(RT_STANDARD)) {
            log.RecordTypeId = rtMap.get(RT_STANDARD);
        } else if ('Change Data Capture'.equals(eventType) && rtMap.containsKey(RT_CDC)) {
            log.RecordTypeId = rtMap.get(RT_CDC);
        } else if (rtMap.containsKey(RT_CUSTOM)) {
            log.RecordTypeId = rtMap.get(RT_CUSTOM);
        }

        insert log;
        return log.Id;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Retrieve recent log records, optionally filtered by channel
    // ──────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static List<Platform_Event_Log__c> getRecentLogs(
        String channel,
        Integer recordLimit,
        String eventType
    ) {
        Integer lmt = (recordLimit != null && recordLimit > 0) ? recordLimit : 50;
        lmt = Math.min(lmt, 200); // cap for safety

        String baseQuery =
            'SELECT Id, Name, Event_API_Name__c, Event_Type__c, Channel__c, ' +
            'Replay_ID__c, Published_By_ID__c, Event_Published_Date__c, ' +
            'Payload__c, Header_Data__c, Schema_ID__c, Subscription_Status__c, ' +
            'Event_UUID__c, Entity_Name__c, Change_Type__c, Changed_Fields__c, ' +
            'Commit_Timestamp__c, Error_Message__c, RecordTypeId, RecordType.Name, ' +
            'CreatedDate ' +
            'FROM Platform_Event_Log__c ';

        List<String> filters = new List<String>();
        if (String.isNotBlank(channel)) {
            filters.add('Channel__c = :channel');
        }
        if (String.isNotBlank(eventType)) {
            filters.add('Event_Type__c = :eventType');
        }

        if (!filters.isEmpty()) {
            baseQuery += 'WHERE ' + String.join(filters, ' AND ') + ' ';
        }

        baseQuery += 'ORDER BY CreatedDate DESC LIMIT :lmt';

        return Database.query(baseQuery);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Update the subscription status of a log record
    // ──────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static void updateLogStatus(Id logId, String status, String errorMessage) {
        Platform_Event_Log__c log = new Platform_Event_Log__c(Id = logId);
        log.Subscription_Status__c = status;
        if (String.isNotBlank(errorMessage)) {
            log.Error_Message__c = errorMessage;
        }
        update log;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Delete all log records for a given channel (useful for housekeeping)
    // ──────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static Integer clearLogsForChannel(String channel) {
        if (String.isBlank(channel)) {
            return 0;
        }
        List<Platform_Event_Log__c> toDelete = [
            SELECT Id FROM Platform_Event_Log__c
            WHERE Channel__c = :channel
            WITH SECURITY_ENFORCED
            LIMIT 200
        ];
        delete toDelete;
        return toDelete.size();
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Helper: generate a UUID v4-style string using Crypto
    // ──────────────────────────────────────────────────────────────────────────
    private static String generateUUID() {
        String hex = EncodingUtil.convertToHex(Crypto.generateAESKey(128));
        return hex.substring(0, 8)  + '-' +
               hex.substring(8, 12) + '-' +
               hex.substring(12, 16) + '-' +
               hex.substring(16, 20) + '-' +
               hex.substring(20, 32);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Helper: safely truncate string to max length
    // ──────────────────────────────────────────────────────────────────────────
    private static String truncate(String s, Integer maxLen) {
        if (s == null) return null;
        return s.length() > maxLen ? s.left(maxLen) : s;
    }
}
