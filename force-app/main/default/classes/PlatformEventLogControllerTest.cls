@IsTest
private class PlatformEventLogControllerTest {

    // ──────────────────────────────────────────────────────────────────────────
    // Test data setup
    // ──────────────────────────────────────────────────────────────────────────
    @TestSetup
    static void makeData() {
        // Pre-warm: nothing needed — controller creates records inline
    }

    // ──────────────────────────────────────────────────────────────────────────
    // createEventLog tests
    // ──────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testCreateEventLog_customEvent_createsRecord() {
        Test.startTest();
        Id logId = PlatformEventLogController.createEventLog(
            'MyOrder__e',
            'Custom Platform Event',
            '/event/MyOrder__e',
            '{"Amount__c":500,"Status__c":"New"}',
            '{"channel":"/event/MyOrder__e","clientId":"abc123"}',
            '999',
            '0051000000XXXXXX',
            '2024-01-15T10:30:00Z',
            'schema-abc-123',
            null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, logId, 'Should return a non-null record Id');

        Platform_Event_Log__c log = [
            SELECT Id, Event_API_Name__c, Event_Type__c, Channel__c,
                   Replay_ID__c, Subscription_Status__c, Event_UUID__c,
                   Schema_ID__c, RecordType.DeveloperName
            FROM Platform_Event_Log__c
            WHERE Id = :logId
        ];

        System.assertEquals('MyOrder__e',            log.Event_API_Name__c);
        System.assertEquals('Custom Platform Event', log.Event_Type__c);
        System.assertEquals('/event/MyOrder__e',     log.Channel__c);
        System.assertEquals('999',                   log.Replay_ID__c);
        System.assertEquals('Received',              log.Subscription_Status__c);
        System.assertNotEquals(null,                 log.Event_UUID__c);
        System.assertEquals('schema-abc-123',        log.Schema_ID__c);
        System.assertEquals('Custom_Platform_Event', log.RecordType.DeveloperName);
    }

    @IsTest
    static void testCreateEventLog_cdcEvent_setsCorrectRecordType() {
        Test.startTest();
        Id logId = PlatformEventLogController.createEventLog(
            'AccountChangeEvent',
            'Change Data Capture',
            '/data/AccountChangeEvent',
            '{"ChangeEventHeader":{"entityName":"Account","changeType":"UPDATE"}}',
            '{}',
            '42',
            '0051000000YYYYYY',
            null,
            null,
            'Account',
            'UPDATE',
            'Name,BillingCity',
            '1705317000000'
        );
        Test.stopTest();

        Platform_Event_Log__c log = [
            SELECT Entity_Name__c, Change_Type__c, Changed_Fields__c,
                   Commit_Timestamp__c, RecordType.DeveloperName
            FROM Platform_Event_Log__c
            WHERE Id = :logId
        ];

        System.assertEquals('Account',              log.Entity_Name__c);
        System.assertEquals('UPDATE',               log.Change_Type__c);
        System.assertEquals('Name,BillingCity',     log.Changed_Fields__c);
        System.assertEquals(1705317000000L,          log.Commit_Timestamp__c.longValue());
        System.assertEquals('Change_Data_Capture',  log.RecordType.DeveloperName);
    }

    @IsTest
    static void testCreateEventLog_standardEvent_setsCorrectRecordType() {
        Test.startTest();
        Id logId = PlatformEventLogController.createEventLog(
            'LoginEvent',
            'Standard Platform Event',
            '/event/LoginEvent',
            '{"UserId":"0051000000ZZZ","LoginType":"Application"}',
            '{}',
            '7',
            '0051000000ZZZZZZ',
            '2024-01-15T08:00:00Z',
            null,
            null, null, null, null
        );
        Test.stopTest();

        Platform_Event_Log__c log = [
            SELECT RecordType.DeveloperName, Event_Published_Date__c
            FROM Platform_Event_Log__c
            WHERE Id = :logId
        ];

        System.assertEquals('Standard_Platform_Event', log.RecordType.DeveloperName);
        System.assertNotEquals(null, log.Event_Published_Date__c, 'Published date should be parsed');
    }

    // ──────────────────────────────────────────────────────────────────────────
    // getRecentLogs tests
    // ──────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testGetRecentLogs_noFilters_returnsAll() {
        createSampleLogs(5, 'Custom Platform Event', '/event/TestEvent__e');
        createSampleLogs(3, 'Change Data Capture',  '/data/AccountChangeEvent');

        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs(null, 20, null);
        Test.stopTest();

        System.assert(results.size() >= 8, 'Should return at least 8 records');
    }

    @IsTest
    static void testGetRecentLogs_channelFilter() {
        createSampleLogs(4, 'Custom Platform Event', '/event/OrderEvent__e');
        createSampleLogs(3, 'Change Data Capture',  '/data/ContactChangeEvent');

        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs('/event/OrderEvent__e', 10, null);
        Test.stopTest();

        System.assertEquals(4, results.size());
        for (Platform_Event_Log__c r : results) {
            System.assertEquals('/event/OrderEvent__e', r.Channel__c);
        }
    }

    @IsTest
    static void testGetRecentLogs_limitRespected() {
        createSampleLogs(10, 'Custom Platform Event', '/event/BulkEvent__e');

        Test.startTest();
        List<Platform_Event_Log__c> results =
            PlatformEventLogController.getRecentLogs(null, 3, null);
        Test.stopTest();

        System.assertEquals(3, results.size(), 'Limit should be respected');
    }

    // ──────────────────────────────────────────────────────────────────────────
    // updateLogStatus tests
    // ──────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testUpdateLogStatus_setsProcessed() {
        Id logId = PlatformEventLogController.createEventLog(
            'TestEvent__e', 'Custom Platform Event', '/event/TestEvent__e',
            '{}', '{}', '1', null, null, null, null, null, null, null
        );

        Test.startTest();
        PlatformEventLogController.updateLogStatus(logId, 'Processed', null);
        Test.stopTest();

        Platform_Event_Log__c log = [
            SELECT Subscription_Status__c FROM Platform_Event_Log__c WHERE Id = :logId
        ];
        System.assertEquals('Processed', log.Subscription_Status__c);
    }

    @IsTest
    static void testUpdateLogStatus_setsError() {
        Id logId = PlatformEventLogController.createEventLog(
            'TestEvent__e', 'Custom Platform Event', '/event/TestEvent__e',
            '{}', '{}', '2', null, null, null, null, null, null, null
        );

        Test.startTest();
        PlatformEventLogController.updateLogStatus(logId, 'Error', 'DML limit exceeded');
        Test.stopTest();

        Platform_Event_Log__c log = [
            SELECT Subscription_Status__c, Error_Message__c
            FROM Platform_Event_Log__c WHERE Id = :logId
        ];
        System.assertEquals('Error', log.Subscription_Status__c);
        System.assertEquals('DML limit exceeded', log.Error_Message__c);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // clearLogsForChannel tests
    // ──────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testClearLogsForChannel_deletesMatchingRecords() {
        createSampleLogs(5, 'Custom Platform Event', '/event/ClearMe__e');
        createSampleLogs(3, 'Custom Platform Event', '/event/KeepMe__e');

        Test.startTest();
        Integer deleted = PlatformEventLogController.clearLogsForChannel('/event/ClearMe__e');
        Test.stopTest();

        System.assertEquals(5, deleted);
        Integer remaining = [
            SELECT COUNT() FROM Platform_Event_Log__c WHERE Channel__c = '/event/ClearMe__e'
        ];
        System.assertEquals(0, remaining);
        Integer kept = [
            SELECT COUNT() FROM Platform_Event_Log__c WHERE Channel__c = '/event/KeepMe__e'
        ];
        System.assertEquals(3, kept);
    }

    @IsTest
    static void testClearLogsForChannel_blankChannel_returnsZero() {
        Test.startTest();
        Integer deleted = PlatformEventLogController.clearLogsForChannel('');
        Test.stopTest();
        System.assertEquals(0, deleted);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // getRecordTypeIds tests
    // ──────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testGetRecordTypeIds_returnsAllThreeTypes() {
        Test.startTest();
        Map<String, String> rtIds = PlatformEventLogController.getRecordTypeIds();
        Test.stopTest();

        System.assert(rtIds.containsKey('Standard_Platform_Event'), 'Missing Standard_Platform_Event RT');
        System.assert(rtIds.containsKey('Change_Data_Capture'),     'Missing Change_Data_Capture RT');
        System.assert(rtIds.containsKey('Custom_Platform_Event'),   'Missing Custom_Platform_Event RT');
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Helper: create N sample log records
    // ──────────────────────────────────────────────────────────────────────────
    private static void createSampleLogs(Integer count, String eventType, String channel) {
        List<Platform_Event_Log__c> logs = new List<Platform_Event_Log__c>();

        Map<String, Id> rtMap = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName FROM RecordType
            WHERE SObjectType = 'Platform_Event_Log__c'
        ]) {
            rtMap.put(rt.DeveloperName, rt.Id);
        }

        String rtKey = eventType == 'Change Data Capture' ? 'Change_Data_Capture' :
                       eventType == 'Standard Platform Event' ? 'Standard_Platform_Event' :
                       'Custom_Platform_Event';

        for (Integer i = 0; i < count; i++) {
            Platform_Event_Log__c log = new Platform_Event_Log__c();
            log.Event_API_Name__c      = channel.substringAfterLast('/');
            log.Event_Type__c          = eventType;
            log.Channel__c             = channel;
            log.Replay_ID__c           = String.valueOf(i);
            log.Subscription_Status__c = 'Received';
            log.Payload__c             = '{"index":' + i + '}';
            log.Header_Data__c         = '{}';
            log.Event_UUID__c          = EncodingUtil.convertToHex(Crypto.generateAESKey(128)).left(32);
            if (rtMap.containsKey(rtKey)) {
                log.RecordTypeId = rtMap.get(rtKey);
            }
            logs.add(log);
        }
        insert logs;
    }
}
