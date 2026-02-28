@IsTest
private class PlatformEventServiceTest {

    @IsTest
    static void testGetAllPlatformEvents_returnsNonEmptyList() {
        Test.startTest();
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();
        Test.stopTest();

        System.assertNotEquals(null, events, 'Event list should not be null');
        // At minimum the standard events hardcoded in the class + AllChangeEvents
        System.assert(events.size() >= 13, 'Should return at least 13 standard events');
    }

    @IsTest
    static void testGetAllPlatformEvents_standardEventsPresent() {
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();

        Map<String, PlatformEventService.PlatformEventInfo> byApiName =
            new Map<String, PlatformEventService.PlatformEventInfo>();
        for (PlatformEventService.PlatformEventInfo e : events) {
            byApiName.put(e.apiName, e);
        }

        System.assert(byApiName.containsKey('LoginEvent'),
            'LoginEvent must be in the list');
        System.assertEquals('/event/LoginEvent',
            byApiName.get('LoginEvent').channel,
            'LoginEvent channel should be /event/LoginEvent');
        System.assertEquals('Standard Platform Event',
            byApiName.get('LoginEvent').eventType,
            'LoginEvent should be Standard Platform Event type');
    }

    @IsTest
    static void testGetAllPlatformEvents_allChangeEventsPresent() {
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();

        Boolean found = false;
        for (PlatformEventService.PlatformEventInfo e : events) {
            if (e.apiName == 'AllChangeEvents') {
                found = true;
                System.assertEquals('/data/ChangeEvents', e.channel);
                System.assertEquals('Change Data Capture', e.eventType);
                break;
            }
        }
        System.assert(found, 'AllChangeEvents meta-channel should be present');
    }

    @IsTest
    static void testGetEventFields_blankName_returnsEmpty() {
        Test.startTest();
        List<PlatformEventService.FieldInfo> fields =
            PlatformEventService.getEventFields('');
        Test.stopTest();

        System.assertNotEquals(null, fields);
        System.assertEquals(0, fields.size(), 'Empty API name should return zero fields');
    }

    @IsTest
    static void testGetEventFields_unknownEvent_returnsEmpty() {
        Test.startTest();
        List<PlatformEventService.FieldInfo> fields =
            PlatformEventService.getEventFields('NonExistentEvent__e');
        Test.stopTest();

        System.assertNotEquals(null, fields);
        System.assertEquals(0, fields.size(), 'Unknown event should return zero fields');
    }
}
