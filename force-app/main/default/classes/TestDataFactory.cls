/**
 * TestDataFactory
 *
 * Centralised factory for all test data used across the Platform Event
 * Monitoring test suite.  Follows the builder / factory separation:
 *
 *   build*()  – constructs the SObject in memory but does NOT call DML.
 *               Use these when you need to customise fields before inserting
 *               or when you are testing logic that does not require persisted
 *               records.
 *
 *   create*() – builds and inserts the record, returning the saved instance.
 *
 * A single EventLogOptions DTO captures every configurable attribute so that
 * callers never need to remember argument order.
 *
 * Mock utilities:
 *   getRecordTypeMap()      – cached SOQL returning real RT Ids (safe for
 *                             injecting into @TestVisible recordTypeCache).
 *   buildMockRecordTypeIds()– map whose values are synthesised fake Ids;
 *                             useful for verifying routing logic without DML
 *                             when only the key assignment matters.
 *   makeFakeId(SObjectType) – generates a syntactically valid but non-persisted
 *                             18-char Salesforce Id for a given SObject type.
 */
@IsTest
public class TestDataFactory {

    // ── Shared constants ──────────────────────────────────────────────────────

    public static final String CHANNEL_CUSTOM   = '/event/TestCustomEvent__e';
    public static final String CHANNEL_CDC      = '/data/AccountChangeEvent';
    public static final String CHANNEL_STANDARD = '/event/LoginEvent';

    public static final String TYPE_CUSTOM   = 'Custom Platform Event';
    public static final String TYPE_CDC      = 'Change Data Capture';
    public static final String TYPE_STANDARD = 'Standard Platform Event';

    public static final String API_CUSTOM   = 'TestCustomEvent__e';
    public static final String API_CDC      = 'AccountChangeEvent';
    public static final String API_STANDARD = 'LoginEvent';

    public static final String PAYLOAD_CUSTOM   = '{"Amount__c":100,"Status__c":"New"}';
    public static final String PAYLOAD_CDC      =
        '{"ChangeEventHeader":{"entityName":"Account","changeType":"UPDATE",' +
        '"changedFields":["Name","BillingCity"],"commitTimestamp":1705317000000}}';
    public static final String PAYLOAD_STANDARD = '{"UserId":"0051000000TestXXX","LoginType":"Application"}';

    // ── Options DTO ───────────────────────────────────────────────────────────

    /**
     * Fluent data-transfer object that carries every configurable attribute for
     * Platform_Event_Log__c.  Defaults mirror the "happy path" custom-event shape
     * so individual tests only need to override the fields they care about.
     */
    public class EventLogOptions {
        public String  apiName            = API_CUSTOM;
        public String  eventType          = TYPE_CUSTOM;
        public String  channel            = CHANNEL_CUSTOM;
        public String  replayId           = '42';
        public String  publishedById      = '0051000000TestAAAAA';
        public String  publishedDate      = '2024-06-15T12:00:00Z';
        public String  payload            = PAYLOAD_CUSTOM;
        public String  headerData         = '{"channel":"' + CHANNEL_CUSTOM + '","clientId":"mock-123"}';
        public String  schemaId           = 'schema-test-001';
        public String  entityName         = null;
        public String  changeType         = null;
        public String  changedFields      = null;
        public String  commitTimestamp    = null;
        public String  subscriptionStatus = 'Received';
        public String  errorMessage       = null;
        public Id      recordTypeId       = null;
    }

    // ── Record type cache (real IDs from org) ────────────────────────────────

    private static Map<String, Id> rtCache;

    /**
     * Returns a map of DeveloperName → Id for all Platform_Event_Log__c record
     * types.  Result is cached so the SOQL runs at most once per test execution.
     */
    public static Map<String, Id> getRecordTypeMap() {
        if (rtCache == null) {
            rtCache = new Map<String, Id>();
            for (RecordType rt : [
                SELECT Id, DeveloperName
                FROM RecordType
                WHERE SObjectType = 'Platform_Event_Log__c'
            ]) {
                rtCache.put(rt.DeveloperName, rt.Id);
            }
        }
        return rtCache;
    }

    /**
     * Returns a map with synthesised (non-persisted) Ids for each record type.
     * Inject this into PlatformEventLogController.recordTypeCache (@TestVisible)
     * to test routing logic in isolation from the org's RecordType table.
     *
     * NOTE: records inserted with these fake RT Ids will fail FK validation.
     * Use this map only when verifying logic that doesn't reach DML, or combine
     * with getRecordTypeMap() to get real Ids when DML is required.
     */
    public static Map<String, Id> buildMockRecordTypeIds() {
        return new Map<String, Id>{
            'Standard_Platform_Event' => makeFakeId(RecordType.SObjectType),
            'Change_Data_Capture'     => makeFakeId(RecordType.SObjectType),
            'Custom_Platform_Event'   => makeFakeId(RecordType.SObjectType)
        };
    }

    // ── build* methods (no DML) ───────────────────────────────────────────────

    /**
     * Builds an unsaved Platform_Event_Log__c from the supplied options,
     * automatically resolving the correct record type from the org's RT table.
     */
    public static Platform_Event_Log__c buildEventLog(EventLogOptions opts) {
        Map<String, Id> rtMap = getRecordTypeMap();

        Platform_Event_Log__c log = new Platform_Event_Log__c();
        log.Event_API_Name__c      = opts.apiName;
        log.Event_Type__c          = opts.eventType;
        log.Channel__c             = opts.channel;
        log.Replay_ID__c           = opts.replayId;
        log.Published_By_ID__c     = opts.publishedById;
        log.Payload__c             = opts.payload;
        log.Header_Data__c         = opts.headerData;
        log.Schema_ID__c           = opts.schemaId;
        log.Subscription_Status__c = opts.subscriptionStatus;
        log.Error_Message__c       = opts.errorMessage;
        log.Entity_Name__c         = opts.entityName;
        log.Change_Type__c         = opts.changeType;
        log.Changed_Fields__c      = opts.changedFields;
        log.Event_UUID__c          = generateUUID();

        if (String.isNotBlank(opts.commitTimestamp)) {
            try { log.Commit_Timestamp__c = Long.valueOf(opts.commitTimestamp); }
            catch (Exception e) { /* ignore malformed values */ }
        }

        if (String.isNotBlank(opts.publishedDate)) {
            try {
                log.Event_Published_Date__c = (DateTime) DateTime.valueOf(
                    opts.publishedDate.replace('T', ' ').replace('Z', '').left(19));
            } catch (Exception e) { /* ignore */ }
        }

        // Resolve record type
        if (opts.recordTypeId != null) {
            log.RecordTypeId = opts.recordTypeId;
        } else {
            String rtKey = opts.eventType == TYPE_CDC      ? 'Change_Data_Capture'     :
                           opts.eventType == TYPE_STANDARD ? 'Standard_Platform_Event' :
                                                             'Custom_Platform_Event';
            if (rtMap.containsKey(rtKey)) {
                log.RecordTypeId = rtMap.get(rtKey);
            }
        }

        return log;
    }

    /** Build an unsaved Custom Platform Event log with default values. */
    public static Platform_Event_Log__c buildCustomEventLog() {
        return buildEventLog(new EventLogOptions());
    }

    /** Build an unsaved Custom Platform Event log for the given channel. */
    public static Platform_Event_Log__c buildCustomEventLog(String channel) {
        EventLogOptions opts = new EventLogOptions();
        opts.channel = channel;
        opts.apiName = channel.substringAfterLast('/');
        return buildEventLog(opts);
    }

    /** Build an unsaved CDC event log. */
    public static Platform_Event_Log__c buildCDCEventLog(
        String channel, String entityName, String changeType, String changedFields
    ) {
        EventLogOptions opts = new EventLogOptions();
        opts.apiName         = channel.substringAfterLast('/');
        opts.eventType       = TYPE_CDC;
        opts.channel         = channel;
        opts.payload         = PAYLOAD_CDC;
        opts.entityName      = entityName;
        opts.changeType      = changeType;
        opts.changedFields   = changedFields;
        opts.commitTimestamp = '1705317000000';
        return buildEventLog(opts);
    }

    /** Build an unsaved Standard Platform Event log. */
    public static Platform_Event_Log__c buildStandardEventLog(String apiName) {
        EventLogOptions opts = new EventLogOptions();
        opts.apiName   = apiName;
        opts.eventType = TYPE_STANDARD;
        opts.channel   = '/event/' + apiName;
        opts.payload   = PAYLOAD_STANDARD;
        return buildEventLog(opts);
    }

    // ── create* methods (with DML) ────────────────────────────────────────────

    /** Build and insert a log using the supplied options. */
    public static Platform_Event_Log__c createEventLog(EventLogOptions opts) {
        Platform_Event_Log__c log = buildEventLog(opts);
        insert log;
        return log;
    }

    /** Build and insert a Custom Platform Event log for the given channel. */
    public static Platform_Event_Log__c createCustomEventLog(String channel) {
        Platform_Event_Log__c log = buildCustomEventLog(channel);
        insert log;
        return log;
    }

    /** Build and insert a CDC event log. */
    public static Platform_Event_Log__c createCDCEventLog(
        String channel, String entityName, String changeType, String changedFields
    ) {
        Platform_Event_Log__c log = buildCDCEventLog(channel, entityName, changeType, changedFields);
        insert log;
        return log;
    }

    /** Build and insert a Standard Platform Event log. */
    public static Platform_Event_Log__c createStandardEventLog(String apiName) {
        Platform_Event_Log__c log = buildStandardEventLog(apiName);
        insert log;
        return log;
    }

    /**
     * Build and insert N logs, each receiving a unique replayId and payload.
     * The base options are cloned so the caller's opts object is never mutated.
     */
    public static List<Platform_Event_Log__c> createEventLogBatch(
        Integer count, EventLogOptions opts
    ) {
        List<Platform_Event_Log__c> logs = new List<Platform_Event_Log__c>();
        for (Integer i = 0; i < count; i++) {
            Platform_Event_Log__c log = buildEventLog(opts);
            log.Replay_ID__c  = String.valueOf(i);
            log.Payload__c    = '{"batchIndex":' + i + '}';
            log.Event_UUID__c = generateUUID();
            logs.add(log);
        }
        insert logs;
        return logs;
    }

    // ── Mock / stub helpers ───────────────────────────────────────────────────

    /**
     * StubProvider implementation for PlatformEventService.
     *
     * Use this as a drop-in for any future LWC Apex controller that takes an
     * injectable PlatformEventService-like dependency.  The pattern shown here
     * follows the Apex Stub API (Test.createStub).
     *
     * Example usage (once a seam exists in the controller):
     *
     *   PlatformEventServiceStub stub = new PlatformEventServiceStub();
     *   stub.stubReturn('getAllPlatformEvents', sampleEvents);
     *   MyController.service =
     *       (IPlatformEventService) Test.createStub(IPlatformEventService.class, stub);
     */
    public class PlatformEventServiceStub implements StubProvider {

        private Map<String, Object> returns = new Map<String, Object>();

        /** Register a return value for a specific method name. */
        public void stubReturn(String methodName, Object returnValue) {
            returns.put(methodName, returnValue);
        }

        public Object handleMethodCall(
            Object stubbedObject,
            String stubbedMethodName,
            Type returnType,
            List<Type> listOfParamTypes,
            List<String> listOfParamNames,
            List<Object> listOfArgs
        ) {
            if (returns.containsKey(stubbedMethodName)) {
                return returns.get(stubbedMethodName);
            }
            return null;
        }
    }

    /**
     * Builds a minimal list of PlatformEventInfo objects for use in stub
     * return values without hitting the Schema API.
     */
    public static List<PlatformEventService.PlatformEventInfo> buildSampleEventInfoList() {
        return new List<PlatformEventService.PlatformEventInfo>{
            new PlatformEventService.PlatformEventInfo(
                'TestCustomEvent__e', 'Test Custom Event',
                TYPE_CUSTOM, '/event/TestCustomEvent__e',
                'A sample custom event'
            ),
            new PlatformEventService.PlatformEventInfo(
                'AccountChangeEvent', 'Account Change Event',
                TYPE_CDC, '/data/AccountChangeEvent',
                'CDC event for Account'
            ),
            new PlatformEventService.PlatformEventInfo(
                'LoginEvent', 'Login Event',
                TYPE_STANDARD, '/event/LoginEvent',
                'Security: user login attempts'
            )
        };
    }

    // ── Utilities ─────────────────────────────────────────────────────────────

    private static Integer fakeIdSeq = 1;

    /**
     * Generates a syntactically valid 18-char Salesforce Id for the given
     * SObject type.  The Id is NOT persisted and will fail FK validation if
     * used in a relationship field on an inserted record.
     */
    public static Id makeFakeId(Schema.SObjectType sot) {
        String prefix = sot.getDescribe().getKeyPrefix();
        return (Id)(prefix + String.valueOf(fakeIdSeq++).leftPad(12, '0'));
    }

    private static String generateUUID() {
        String hex = EncodingUtil.convertToHex(Crypto.generateAESKey(128));
        return hex.substring(0, 8)  + '-' + hex.substring(8, 12)  + '-' +
               hex.substring(12, 16) + '-' + hex.substring(16, 20) + '-' +
               hex.substring(20, 32);
    }
}
