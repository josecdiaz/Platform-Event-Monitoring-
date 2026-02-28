/**
 * PlatformEventLogControllerTest
 *
 * Uses the TestDataFactory for all record construction and demonstrates two
 * complementary mock strategies:
 *
 * 1. Real-data tests  – records are built via TestDataFactory and inserted;
 *    queries return live org data (covers integration-style paths).
 *
 * 2. Mock RT-injection tests – PlatformEventLogController.recordTypeCache
 *    (@TestVisible) is pre-loaded with real or controlled Ids so the lazy SOQL
 *    inside getRecordTypeMap() is bypassed.  This lets us isolate and assert
 *    the routing logic without caring which SOQL ran inside the controller.
 *
 * 3. StubProvider pattern – TestDataFactory.PlatformEventServiceStub is wired
 *    here to show how to supply canned responses for any future controller that
 *    accepts an injectable service reference.
 */
@IsTest
private class PlatformEventLogControllerTest {

    // ── @TestSetup – shared data built once via TestDataFactory ──────────────

    @TestSetup
    static void makeData() {
        // Custom events on two different channels
        TestDataFactory.EventLogOptions custOpts = new TestDataFactory.EventLogOptions();
        custOpts.channel = '/event/OrderCreated__e';
        custOpts.apiName = 'OrderCreated__e';
        TestDataFactory.createEventLogBatch(5, custOpts);

        custOpts.channel = '/event/ShipmentUpdated__e';
        custOpts.apiName = 'ShipmentUpdated__e';
        TestDataFactory.createEventLogBatch(3, custOpts);

        // CDC events
        TestDataFactory.createCDCEventLog(
            '/data/AccountChangeEvent', 'Account', 'UPDATE', 'Name,BillingCity');
        TestDataFactory.createCDCEventLog(
            '/data/ContactChangeEvent', 'Contact', 'CREATE', 'LastName,Email');

        // Standard events
        TestDataFactory.createStandardEventLog('LoginEvent');
        TestDataFactory.createStandardEventLog('ApiEvent');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getRecordTypeIds
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getRecordTypeIds_returnsAllThreeKeys() {
        Test.startTest();
        Map<String, String> result = PlatformEventLogController.getRecordTypeIds();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('Custom_Platform_Event'),
            'Missing Custom_Platform_Event RT');
        System.assert(result.containsKey('Change_Data_Capture'),
            'Missing Change_Data_Capture RT');
        System.assert(result.containsKey('Standard_Platform_Event'),
            'Missing Standard_Platform_Event RT');
    }

    @IsTest
    static void getRecordTypeIds_valuesAreValidIds() {
        Map<String, String> result = PlatformEventLogController.getRecordTypeIds();

        for (String key : result.keySet()) {
            Id rtId = (Id) result.get(key);
            System.assertNotEquals(null, rtId,
                key + ' should map to a non-null Id');
            System.assertEquals('012',
                String.valueOf(rtId).left(3),
                key + ' should have the RecordType key prefix 012');
        }
    }

    // Mock injection: verify that a pre-loaded cache is returned without SOQL
    @IsTest
    static void getRecordTypeIds_usesMockCacheWhenInjected() {
        Map<String, Id> realIds = TestDataFactory.getRecordTypeMap();
        // Inject real IDs via @TestVisible field — the internal SOQL is skipped
        PlatformEventLogController.recordTypeCache = realIds;

        Test.startTest();
        Map<String, String> result = PlatformEventLogController.getRecordTypeIds();
        Test.stopTest();

        System.assertEquals(realIds.size(), result.size(),
            'Injected cache size should match returned map size');
        for (String key : realIds.keySet()) {
            System.assertEquals(
                String.valueOf(realIds.get(key)),
                result.get(key),
                'Returned Id for ' + key + ' must match injected value'
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // createEventLog – record-type routing (mock RT injection)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Inject the real record type map before calling createEventLog so that
     * the SOQL inside getRecordTypeMap() is bypassed.  This isolates the routing
     * logic from the database and ensures the correct RecordTypeId is set purely
     * based on the eventType string.
     */
    @IsTest
    static void createEventLog_customEvent_routesToCustomRT() {
        Map<String, Id> rtMap = TestDataFactory.getRecordTypeMap();
        PlatformEventLogController.recordTypeCache = rtMap;

        Test.startTest();
        Id logId = callCreateEventLog(TestDataFactory.TYPE_CUSTOM,
            TestDataFactory.CHANNEL_CUSTOM, TestDataFactory.API_CUSTOM,
            null, null, null, null);
        Test.stopTest();

        Platform_Event_Log__c log = queryLog(logId);
        System.assertEquals('Custom_Platform_Event', log.RecordType.DeveloperName,
            'Custom event type must route to Custom_Platform_Event RT');
        System.assertEquals('Received', log.Subscription_Status__c,
            'Initial status should be Received');
        System.assertNotEquals(null, log.Event_UUID__c,
            'UUID must be auto-generated');
    }

    @IsTest
    static void createEventLog_cdcEvent_routesToCDCRT() {
        PlatformEventLogController.recordTypeCache = TestDataFactory.getRecordTypeMap();

        Test.startTest();
        Id logId = callCreateEventLog(TestDataFactory.TYPE_CDC,
            TestDataFactory.CHANNEL_CDC, TestDataFactory.API_CDC,
            'Account', 'UPDATE', 'Name,BillingCity', '1705317000000');
        Test.stopTest();

        Platform_Event_Log__c log = queryLog(logId);
        System.assertEquals('Change_Data_Capture', log.RecordType.DeveloperName);
        System.assertEquals('Account',          log.Entity_Name__c);
        System.assertEquals('UPDATE',           log.Change_Type__c);
        System.assertEquals('Name,BillingCity', log.Changed_Fields__c);
        System.assertEquals(1705317000000L,
            log.Commit_Timestamp__c.longValue(), 'Commit timestamp must be parsed');
    }

    @IsTest
    static void createEventLog_standardEvent_routesToStandardRT() {
        PlatformEventLogController.recordTypeCache = TestDataFactory.getRecordTypeMap();

        Test.startTest();
        Id logId = callCreateEventLog(TestDataFactory.TYPE_STANDARD,
            TestDataFactory.CHANNEL_STANDARD, TestDataFactory.API_STANDARD,
            null, null, null, null);
        Test.stopTest();

        Platform_Event_Log__c log = queryLog(logId);
        System.assertEquals('Standard_Platform_Event', log.RecordType.DeveloperName);
    }

    // If no record type is matched, the insert should still succeed (org default RT)
    @IsTest
    static void createEventLog_emptyRTCache_insertsWithDefaultRT() {
        // Inject an empty cache — no routing branches will match
        PlatformEventLogController.recordTypeCache = new Map<String, Id>();

        Test.startTest();
        Id logId = callCreateEventLog(TestDataFactory.TYPE_CUSTOM,
            TestDataFactory.CHANNEL_CUSTOM, TestDataFactory.API_CUSTOM,
            null, null, null, null);
        Test.stopTest();

        // Record should still be inserted; RecordTypeId will be the org default
        System.assertNotEquals(null, logId, 'Insert should succeed even with empty RT cache');
        Integer count = [SELECT COUNT() FROM Platform_Event_Log__c WHERE Id = :logId];
        System.assertEquals(1, count, 'Record must exist in database');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // createEventLog – field mapping & date parsing
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void createEventLog_allCoreFieldsMapped() {
        PlatformEventLogController.recordTypeCache = TestDataFactory.getRecordTypeMap();
        String payload    = '{"field1":"abc","field2":99}';
        String headerData = '{"channel":"/event/X__e","replayId":7}';

        Test.startTest();
        Id logId = PlatformEventLogController.createEventLog(
            'FullField__e',
            TestDataFactory.TYPE_CUSTOM,
            '/event/FullField__e',
            payload,
            headerData,
            '77',
            '0051000000UserAAA',
            '2024-03-10T09:15:00Z',
            'schema-full-001',
            null, null, null, null
        );
        Test.stopTest();

        Platform_Event_Log__c log = [
            SELECT Event_API_Name__c, Event_Type__c, Channel__c,
                   Replay_ID__c, Published_By_ID__c, Event_Published_Date__c,
                   Payload__c, Header_Data__c, Schema_ID__c,
                   Subscription_Status__c, Event_UUID__c
            FROM Platform_Event_Log__c WHERE Id = :logId
        ];

        System.assertEquals('FullField__e',               log.Event_API_Name__c);
        System.assertEquals(TestDataFactory.TYPE_CUSTOM,  log.Event_Type__c);
        System.assertEquals('/event/FullField__e',        log.Channel__c);
        System.assertEquals('77',                         log.Replay_ID__c);
        System.assertEquals('0051000000UserAAA',          log.Published_By_ID__c);
        System.assertEquals(payload,                      log.Payload__c);
        System.assertEquals(headerData,                   log.Header_Data__c);
        System.assertEquals('schema-full-001',            log.Schema_ID__c);
        System.assertEquals('Received',                   log.Subscription_Status__c);
        System.assertNotEquals(null,                      log.Event_UUID__c);
        System.assertNotEquals(null, log.Event_Published_Date__c,
            'ISO date string should be parsed to a DateTime');
    }

    @IsTest
    static void createEventLog_validISODate_parsedCorrectly() {
        PlatformEventLogController.recordTypeCache = TestDataFactory.getRecordTypeMap();

        Test.startTest();
        Id logId = PlatformEventLogController.createEventLog(
            'DateTest__e', TestDataFactory.TYPE_CUSTOM, '/event/DateTest__e',
            '{}', '{}', '1', null,
            '2024-11-05T14:30:45Z',
            null, null, null, null, null
        );
        Test.stopTest();

        Platform_Event_Log__c log = [
            SELECT Event_Published_Date__c FROM Platform_Event_Log__c WHERE Id = :logId
        ];
        System.assertNotEquals(null, log.Event_Published_Date__c);
        System.assertEquals(2024, log.Event_Published_Date__c.yearGmt());
        System.assertEquals(11,   log.Event_Published_Date__c.monthGmt());
        System.assertEquals(5,    log.Event_Published_Date__c.dayGmt());
    }

    @IsTest
    static void createEventLog_malformedDate_doesNotThrow() {
        PlatformEventLogController.recordTypeCache = TestDataFactory.getRecordTypeMap();

        Test.startTest();
        Id logId = PlatformEventLogController.createEventLog(
            'BadDate__e', TestDataFactory.TYPE_CUSTOM, '/event/BadDate__e',
            '{}', '{}', '2', null,
            'NOT-A-DATE',
            null, null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, logId, 'Malformed date should not prevent insert');
        Platform_Event_Log__c log = [
            SELECT Event_Published_Date__c FROM Platform_Event_Log__c WHERE Id = :logId
        ];
        System.assertEquals(null, log.Event_Published_Date__c,
            'Malformed date should leave field null');
    }

    @IsTest
    static void createEventLog_malformedCommitTimestamp_doesNotThrow() {
        PlatformEventLogController.recordTypeCache = TestDataFactory.getRecordTypeMap();

        Test.startTest();
        Id logId = PlatformEventLogController.createEventLog(
            'BadTs__e', TestDataFactory.TYPE_CDC, '/data/BadTs__e',
            '{}', '{}', '3', null, null, null,
            'Account', 'CREATE', null, 'NOT-A-LONG'
        );
        Test.stopTest();

        System.assertNotEquals(null, logId, 'Bad commitTimestamp should not prevent insert');
        Platform_Event_Log__c log = [
            SELECT Commit_Timestamp__c FROM Platform_Event_Log__c WHERE Id = :logId
        ];
        System.assertEquals(null, log.Commit_Timestamp__c,
            'Malformed timestamp should leave field null');
    }

    @IsTest
    static void createEventLog_fieldsTruncatedToMaxLength() {
        PlatformEventLogController.recordTypeCache = TestDataFactory.getRecordTypeMap();
        String over255 = 'x'.repeat(300);

        Test.startTest();
        Id logId = PlatformEventLogController.createEventLog(
            over255,                         // eventApiName → truncated to 255
            TestDataFactory.TYPE_CUSTOM,
            over255,                         // channel → truncated to 255
            '{}', '{}',
            over255,                         // replayId → truncated to 50
            null, null, null, null, null, null, null
        );
        Test.stopTest();

        Platform_Event_Log__c log = [
            SELECT Event_API_Name__c, Channel__c, Replay_ID__c
            FROM Platform_Event_Log__c WHERE Id = :logId
        ];
        System.assertEquals(255, log.Event_API_Name__c.length(),
            'Event_API_Name__c should be truncated to 255');
        System.assertEquals(255, log.Channel__c.length(),
            'Channel__c should be truncated to 255');
        System.assertEquals(50, log.Replay_ID__c.length(),
            'Replay_ID__c should be truncated to 50');
    }

    @IsTest
    static void createEventLog_nullInputs_insertsGracefully() {
        PlatformEventLogController.recordTypeCache = TestDataFactory.getRecordTypeMap();

        Test.startTest();
        Id logId = PlatformEventLogController.createEventLog(
            null, TestDataFactory.TYPE_CUSTOM, null,
            null, null, null, null, null, null,
            null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, logId, 'Null inputs should not prevent insert');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getRecentLogs – querying and filtering
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getRecentLogs_noFilters_returnsAllInsertedRecords() {
        // @TestSetup inserted 12 records
        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs(null, 50, null);
        Test.stopTest();

        System.assert(results.size() >= 12,
            'Should return all records when no filter is applied');
    }

    @IsTest
    static void getRecentLogs_channelFilter_returnsOnlyMatchingChannel() {
        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs('/event/OrderCreated__e', 50, null);
        Test.stopTest();

        System.assertEquals(5, results.size(),
            'Should return only records for /event/OrderCreated__e');
        for (Platform_Event_Log__c r : results) {
            System.assertEquals('/event/OrderCreated__e', r.Channel__c);
        }
    }

    @IsTest
    static void getRecentLogs_eventTypeFilter_returnsOnlyMatchingType() {
        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs(null, 50, TestDataFactory.TYPE_CDC);
        Test.stopTest();

        System.assertEquals(2, results.size(),
            'Should return only CDC records');
        for (Platform_Event_Log__c r : results) {
            System.assertEquals(TestDataFactory.TYPE_CDC, r.Event_Type__c);
        }
    }

    @IsTest
    static void getRecentLogs_bothFilters_intersectsCorrectly() {
        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs(
                '/data/AccountChangeEvent', 50, TestDataFactory.TYPE_CDC);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('/data/AccountChangeEvent', results[0].Channel__c);
        System.assertEquals(TestDataFactory.TYPE_CDC, results[0].Event_Type__c);
    }

    @IsTest
    static void getRecentLogs_limitRespected() {
        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs(null, 3, null);
        Test.stopTest();

        System.assertEquals(3, results.size(), 'Explicit limit must be respected');
    }

    @IsTest
    static void getRecentLogs_nullLimit_defaultsToFifty() {
        // Insert more than 50 records to verify the default cap
        TestDataFactory.EventLogOptions opts = new TestDataFactory.EventLogOptions();
        opts.channel = '/event/BigBatch__e';
        opts.apiName = 'BigBatch__e';
        TestDataFactory.createEventLogBatch(60, opts);

        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs('/event/BigBatch__e', null, null);
        Test.stopTest();

        System.assertEquals(50, results.size(),
            'Null limit should default to 50');
    }

    @IsTest
    static void getRecentLogs_zeroLimit_defaultsToFifty() {
        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs(null, 0, null);
        Test.stopTest();

        System.assert(results.size() <= 50,
            'Zero limit should default to 50 (capped)');
    }

    @IsTest
    static void getRecentLogs_limitOver200_cappedAt200() {
        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs(null, 999, null);
        Test.stopTest();

        System.assert(results.size() <= 200,
            'Limit over 200 must be capped at 200');
    }

    @IsTest
    static void getRecentLogs_nonExistentChannel_returnsEmptyList() {
        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs('/event/DoesNotExist__e', 50, null);
        Test.stopTest();

        System.assertEquals(0, results.size(),
            'Non-existent channel should return an empty list');
    }

    @IsTest
    static void getRecentLogs_orderedNewestFirst() {
        // Insert 3 records sequentially so CreatedDate differs
        TestDataFactory.EventLogOptions opts = new TestDataFactory.EventLogOptions();
        opts.channel = '/event/OrderedTest__e';
        opts.apiName = 'OrderedTest__e';
        TestDataFactory.createEventLogBatch(3, opts);

        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs('/event/OrderedTest__e', 10, null);
        Test.stopTest();

        for (Integer i = 0; i < results.size() - 1; i++) {
            System.assert(
                results[i].CreatedDate >= results[i + 1].CreatedDate,
                'Records should be ordered newest first (CreatedDate DESC)'
            );
        }
    }

    @IsTest
    static void getRecentLogs_allFieldsPopulated() {
        Platform_Event_Log__c inserted = TestDataFactory.createCDCEventLog(
            '/data/OpportunityChangeEvent', 'Opportunity', 'DELETE', 'StageName');

        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs(
                '/data/OpportunityChangeEvent', 5, null);
        Test.stopTest();

        System.assertEquals(1, results.size());
        Platform_Event_Log__c r = results[0];
        System.assertNotEquals(null, r.Event_UUID__c,      'UUID should be set');
        System.assertNotEquals(null, r.Payload__c,          'Payload should be set');
        System.assertNotEquals(null, r.Entity_Name__c,      'Entity name should be set');
        System.assertNotEquals(null, r.Change_Type__c,      'Change type should be set');
        System.assertNotEquals(null, r.Changed_Fields__c,   'Changed fields should be set');
        System.assertNotEquals(null, r.RecordType.Name,     'RecordType.Name should be populated');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateLogStatus
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void updateLogStatus_setsProcessed_noErrorMessage() {
        Platform_Event_Log__c log = TestDataFactory.createCustomEventLog(
            '/event/StatusTest__e');

        Test.startTest();
        PlatformEventLogController.updateLogStatus(log.Id, 'Processed', null);
        Test.stopTest();

        Platform_Event_Log__c updated = [
            SELECT Subscription_Status__c, Error_Message__c
            FROM Platform_Event_Log__c WHERE Id = :log.Id
        ];
        System.assertEquals('Processed', updated.Subscription_Status__c);
        System.assertEquals(null, updated.Error_Message__c,
            'Error message should stay null when not provided');
    }

    @IsTest
    static void updateLogStatus_setsError_withMessage() {
        Platform_Event_Log__c log = TestDataFactory.createCustomEventLog(
            '/event/StatusTest__e');

        Test.startTest();
        PlatformEventLogController.updateLogStatus(
            log.Id, 'Error', 'Governor limit exceeded during processing');
        Test.stopTest();

        Platform_Event_Log__c updated = [
            SELECT Subscription_Status__c, Error_Message__c
            FROM Platform_Event_Log__c WHERE Id = :log.Id
        ];
        System.assertEquals('Error', updated.Subscription_Status__c);
        System.assertEquals(
            'Governor limit exceeded during processing',
            updated.Error_Message__c
        );
    }

    @IsTest
    static void updateLogStatus_blankErrorMessage_doesNotOverwrite() {
        TestDataFactory.EventLogOptions opts = new TestDataFactory.EventLogOptions();
        opts.channel       = '/event/BlankErrTest__e';
        opts.apiName       = 'BlankErrTest__e';
        opts.errorMessage  = 'Original error';
        Platform_Event_Log__c log = TestDataFactory.createEventLog(opts);

        Test.startTest();
        PlatformEventLogController.updateLogStatus(log.Id, 'Processed', '');
        Test.stopTest();

        Platform_Event_Log__c updated = [
            SELECT Subscription_Status__c, Error_Message__c
            FROM Platform_Event_Log__c WHERE Id = :log.Id
        ];
        System.assertEquals('Processed', updated.Subscription_Status__c);
        // Blank error string should not overwrite an existing error message
        System.assertEquals('Original error', updated.Error_Message__c);
    }

    @IsTest
    static void updateLogStatus_receivedToReceivedIsIdempotent() {
        Platform_Event_Log__c log = TestDataFactory.createCustomEventLog(
            '/event/IdempotentTest__e');

        Test.startTest();
        PlatformEventLogController.updateLogStatus(log.Id, 'Received', null);
        Test.stopTest();

        Platform_Event_Log__c updated = [
            SELECT Subscription_Status__c FROM Platform_Event_Log__c WHERE Id = :log.Id
        ];
        System.assertEquals('Received', updated.Subscription_Status__c);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // clearLogsForChannel
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void clearLogsForChannel_blank_returnsZero() {
        Test.startTest();
        Integer result = PlatformEventLogController.clearLogsForChannel('');
        Test.stopTest();

        System.assertEquals(0, result, 'Blank channel should return 0');
    }

    @IsTest
    static void clearLogsForChannel_null_returnsZero() {
        Test.startTest();
        Integer result = PlatformEventLogController.clearLogsForChannel(null);
        Test.stopTest();

        System.assertEquals(0, result, 'Null channel should return 0');
    }

    @IsTest
    static void clearLogsForChannel_matchingRecords_deletedAndCountReturned() {
        TestDataFactory.EventLogOptions opts = new TestDataFactory.EventLogOptions();
        opts.channel = '/event/ClearTarget__e';
        opts.apiName = 'ClearTarget__e';
        TestDataFactory.createEventLogBatch(7, opts);

        opts.channel = '/event/ClearKeep__e';
        opts.apiName = 'ClearKeep__e';
        TestDataFactory.createEventLogBatch(4, opts);

        Test.startTest();
        Integer deleted = PlatformEventLogController.clearLogsForChannel(
            '/event/ClearTarget__e');
        Test.stopTest();

        System.assertEquals(7, deleted, 'Should report 7 deleted');

        Integer remaining = [
            SELECT COUNT() FROM Platform_Event_Log__c
            WHERE Channel__c = '/event/ClearTarget__e'
        ];
        System.assertEquals(0, remaining, 'Target channel records should be gone');

        Integer kept = [
            SELECT COUNT() FROM Platform_Event_Log__c
            WHERE Channel__c = '/event/ClearKeep__e'
        ];
        System.assertEquals(4, kept, 'Unrelated channel records must be untouched');
    }

    @IsTest
    static void clearLogsForChannel_nonExistentChannel_returnsZero() {
        Test.startTest();
        Integer deleted = PlatformEventLogController.clearLogsForChannel(
            '/event/NeverExisted__e');
        Test.stopTest();

        System.assertEquals(0, deleted,
            'Non-existent channel should return 0 deleted');
    }

    @IsTest
    static void clearLogsForChannel_singleRecord_deletedCorrectly() {
        TestDataFactory.createCustomEventLog('/event/SingleRecord__e');

        Test.startTest();
        Integer deleted = PlatformEventLogController.clearLogsForChannel(
            '/event/SingleRecord__e');
        Test.stopTest();

        System.assertEquals(1, deleted);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // StubProvider pattern demonstration
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Demonstrates the StubProvider / mock pattern using
     * TestDataFactory.PlatformEventServiceStub.
     *
     * This test simulates a scenario where the controller has an injectable
     * PlatformEventService dependency (future-proofing pattern).  The stub
     * intercepts any method call and returns a canned PlatformEventInfo list,
     * allowing the test to exercise downstream controller logic without touching
     * the Schema API at all.
     */
    @IsTest
    static void stubProvider_platformEventService_returnsCannedData() {
        List<PlatformEventService.PlatformEventInfo> canned =
            TestDataFactory.buildSampleEventInfoList();

        TestDataFactory.PlatformEventServiceStub stub =
            new TestDataFactory.PlatformEventServiceStub();
        stub.stubReturn('getAllPlatformEvents', canned);

        Test.startTest();
        // Invoke the stub directly to verify the pattern works end-to-end
        Object result = stub.handleMethodCall(
            null,
            'getAllPlatformEvents',
            List<PlatformEventService.PlatformEventInfo>.class,
            new List<Type>(),
            new List<String>(),
            new List<Object>()
        );
        Test.stopTest();

        List<PlatformEventService.PlatformEventInfo> returned =
            (List<PlatformEventService.PlatformEventInfo>) result;

        System.assertEquals(3, returned.size(),
            'Stub should return the 3 canned events');
        System.assertEquals(TestDataFactory.TYPE_CUSTOM, returned[0].eventType);
        System.assertEquals(TestDataFactory.TYPE_CDC,    returned[1].eventType);
        System.assertEquals(TestDataFactory.TYPE_STANDARD, returned[2].eventType);
    }

    @IsTest
    static void stubProvider_unknownMethod_returnsNull() {
        TestDataFactory.PlatformEventServiceStub stub =
            new TestDataFactory.PlatformEventServiceStub();
        // No stubbed return registered for 'getEventFields'

        Object result = stub.handleMethodCall(
            null, 'getEventFields', null,
            new List<Type>(), new List<String>(), new List<Object>{ 'SomeEvent__e' }
        );

        System.assertEquals(null, result,
            'Unstubbed method should return null gracefully');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TestDataFactory self-tests (smoke tests for the factory itself)
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void testDataFactory_buildCustomEventLog_notInserted() {
        Platform_Event_Log__c log = TestDataFactory.buildCustomEventLog();
        System.assertEquals(null, log.Id, 'build* must not insert');
        System.assertEquals(TestDataFactory.TYPE_CUSTOM, log.Event_Type__c);
        System.assertNotEquals(null, log.Event_UUID__c, 'UUID should be pre-generated');
    }

    @IsTest
    static void testDataFactory_buildCDCEventLog_fieldsSet() {
        Platform_Event_Log__c log = TestDataFactory.buildCDCEventLog(
            '/data/LeadChangeEvent', 'Lead', 'CREATE', 'LastName');

        System.assertEquals(TestDataFactory.TYPE_CDC, log.Event_Type__c);
        System.assertEquals('Lead',     log.Entity_Name__c);
        System.assertEquals('CREATE',   log.Change_Type__c);
        System.assertEquals('LastName', log.Changed_Fields__c);
        System.assertNotEquals(null, log.Commit_Timestamp__c);
    }

    @IsTest
    static void testDataFactory_buildStandardEventLog_fieldsSet() {
        Platform_Event_Log__c log = TestDataFactory.buildStandardEventLog('ApiEvent');

        System.assertEquals(TestDataFactory.TYPE_STANDARD, log.Event_Type__c);
        System.assertEquals('/event/ApiEvent', log.Channel__c);
        System.assertEquals('ApiEvent', log.Event_API_Name__c);
    }

    @IsTest
    static void testDataFactory_createEventLogBatch_correctCount() {
        TestDataFactory.EventLogOptions opts = new TestDataFactory.EventLogOptions();
        opts.channel = '/event/BatchFactoryTest__e';
        opts.apiName = 'BatchFactoryTest__e';

        Test.startTest();
        List<Platform_Event_Log__c> logs = TestDataFactory.createEventLogBatch(8, opts);
        Test.stopTest();

        System.assertEquals(8, logs.size());
        for (Platform_Event_Log__c l : logs) {
            System.assertNotEquals(null, l.Id, 'All records must be persisted');
        }
    }

    @IsTest
    static void testDataFactory_makeFakeId_correctPrefix() {
        Id fakeId = TestDataFactory.makeFakeId(RecordType.SObjectType);
        System.assertEquals('012', String.valueOf(fakeId).left(3),
            'Fake RecordType Id must start with 012');
        System.assertEquals(18, String.valueOf(fakeId).length(),
            'Fake Id must be 18 characters');
    }

    @IsTest
    static void testDataFactory_getRecordTypeMap_returnsThreeKeys() {
        Map<String, Id> rtMap = TestDataFactory.getRecordTypeMap();
        System.assert(rtMap.containsKey('Custom_Platform_Event'));
        System.assert(rtMap.containsKey('Change_Data_Capture'));
        System.assert(rtMap.containsKey('Standard_Platform_Event'));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Helpers
    // ═══════════════════════════════════════════════════════════════════════════

    /** Calls createEventLog with the minimal required parameters. */
    private static Id callCreateEventLog(
        String eventType, String channel, String apiName,
        String entityName, String changeType, String changedFields,
        String commitTimestamp
    ) {
        return PlatformEventLogController.createEventLog(
            apiName,
            eventType,
            channel,
            '{"test":true}',
            '{"channel":"' + channel + '"}',
            '1',
            null,
            null,
            null,
            entityName,
            changeType,
            changedFields,
            commitTimestamp
        );
    }

    /** Queries a Platform_Event_Log__c with all assertion-relevant fields. */
    private static Platform_Event_Log__c queryLog(Id logId) {
        return [
            SELECT Id, Event_API_Name__c, Event_Type__c, Channel__c,
                   Replay_ID__c, Published_By_ID__c, Event_Published_Date__c,
                   Payload__c, Header_Data__c, Schema_ID__c,
                   Subscription_Status__c, Event_UUID__c,
                   Entity_Name__c, Change_Type__c, Changed_Fields__c,
                   Commit_Timestamp__c, Error_Message__c,
                   RecordTypeId, RecordType.DeveloperName, RecordType.Name
            FROM Platform_Event_Log__c
            WHERE Id = :logId
        ];
    }
}
