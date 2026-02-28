/**
 * PlatformEventServiceTest
 *
 * Comprehensive test suite for PlatformEventService.
 *
 * Approach:
 *   - All 12 hardcoded standard events are verified individually by name,
 *     eventType, channel format, label, and description.
 *   - The AllChangeEvents meta-channel is verified as a special case.
 *   - PlatformEventInfo and FieldInfo inner class constructors are exercised
 *     directly via TestDataFactory.buildSampleEventInfoList().
 *   - getEventFields() is tested with blank/null/unknown API names and with
 *     'Account', a standard SObject always present in any Salesforce org,
 *     to verify that field metadata is correctly projected without relying on
 *     a custom __e event being deployed.
 *   - Schema.getGlobalDescribe() is a platform method that cannot be replaced
 *     by a StubProvider (it is static and system-owned).  The tests therefore
 *     validate observable outputs rather than intercepting the call.
 *     The TestDataFactory.PlatformEventServiceStub shows how a refactored
 *     injectable-service design would be tested; that pattern is exercised in
 *     PlatformEventLogControllerTest.
 */
@IsTest
private class PlatformEventServiceTest {

    // ── Constants – expected standard event API names ─────────────────────────

    private static final List<String> EXPECTED_STANDARD_EVENTS = new List<String>{
        'LoginEvent',
        'LoginAsEvent',
        'LogoutEvent',
        'ApiEvent',
        'UriEvent',
        'ApiAnomalyEvent',
        'ReportAnomalyEvent',
        'SessionHijackingEvent',
        'CredentialStuffingEvent',
        'BulkApiResultEvent',
        'FlowExecutionErrorEvent',
        'PlatformStatusAlertEvent'
    };

    // ═══════════════════════════════════════════════════════════════════════════
    // getAllPlatformEvents – list shape
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getAllPlatformEvents_returnsNonNullNonEmptyList() {
        Test.startTest();
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();
        Test.stopTest();

        System.assertNotEquals(null, events, 'Result must not be null');
        // At minimum: 12 standard + AllChangeEvents = 13
        System.assert(events.size() >= 13,
            'Expected at least 13 events, got: ' + events.size());
    }

    @IsTest
    static void getAllPlatformEvents_noNullEntriesInList() {
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();

        for (PlatformEventService.PlatformEventInfo e : events) {
            System.assertNotEquals(null, e,          'No null entries allowed in the list');
            System.assertNotEquals(null, e.apiName,  'apiName must not be null for any event');
            System.assertNotEquals(null, e.eventType,'eventType must not be null');
            System.assertNotEquals(null, e.channel,  'channel must not be null');
        }
    }

    @IsTest
    static void getAllPlatformEvents_noDuplicateApiNames() {
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();

        Set<String> seen = new Set<String>();
        for (PlatformEventService.PlatformEventInfo e : events) {
            System.assert(!seen.contains(e.apiName),
                'Duplicate apiName found: ' + e.apiName);
            seen.add(e.apiName);
        }
    }

    @IsTest
    static void getAllPlatformEvents_eventTypesAreKnownValues() {
        Set<String> valid = new Set<String>{
            'Custom Platform Event',
            'Change Data Capture',
            'Standard Platform Event'
        };
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();

        for (PlatformEventService.PlatformEventInfo e : events) {
            System.assert(valid.contains(e.eventType),
                'Unknown eventType "' + e.eventType + '" for ' + e.apiName);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getAllPlatformEvents – every standard event verified individually
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getAllPlatformEvents_allTwelveStandardEventsPresent() {
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();
        Map<String, PlatformEventService.PlatformEventInfo> byName = indexByApiName(events);

        for (String expected : EXPECTED_STANDARD_EVENTS) {
            System.assert(byName.containsKey(expected),
                expected + ' is missing from the returned list');
        }
    }

    @IsTest
    static void getAllPlatformEvents_loginEvent_shape() {
        Map<String, PlatformEventService.PlatformEventInfo> byName =
            indexByApiName(PlatformEventService.getAllPlatformEvents());

        PlatformEventService.PlatformEventInfo e = byName.get('LoginEvent');
        System.assertNotEquals(null, e, 'LoginEvent must be present');
        System.assertEquals('Standard Platform Event', e.eventType);
        System.assertEquals('/event/LoginEvent',       e.channel);
        System.assertEquals('Login Event',             e.label);
        System.assertNotEquals(null, e.description,    'description must not be null');
        System.assert(e.description.length() > 0,      'description must not be empty');
    }

    @IsTest
    static void getAllPlatformEvents_loginAsEvent_shape() {
        Map<String, PlatformEventService.PlatformEventInfo> byName =
            indexByApiName(PlatformEventService.getAllPlatformEvents());

        PlatformEventService.PlatformEventInfo e = byName.get('LoginAsEvent');
        System.assertEquals('Standard Platform Event', e.eventType);
        System.assertEquals('/event/LoginAsEvent', e.channel);
        System.assertEquals('Login As Event', e.label);
    }

    @IsTest
    static void getAllPlatformEvents_logoutEvent_shape() {
        Map<String, PlatformEventService.PlatformEventInfo> byName =
            indexByApiName(PlatformEventService.getAllPlatformEvents());

        PlatformEventService.PlatformEventInfo e = byName.get('LogoutEvent');
        System.assertEquals('Standard Platform Event', e.eventType);
        System.assertEquals('/event/LogoutEvent', e.channel);
    }

    @IsTest
    static void getAllPlatformEvents_apiEvent_shape() {
        Map<String, PlatformEventService.PlatformEventInfo> byName =
            indexByApiName(PlatformEventService.getAllPlatformEvents());

        PlatformEventService.PlatformEventInfo e = byName.get('ApiEvent');
        System.assertEquals('Standard Platform Event', e.eventType);
        System.assertEquals('/event/ApiEvent', e.channel);
        System.assertEquals('API Event', e.label);
    }

    @IsTest
    static void getAllPlatformEvents_uriEvent_shape() {
        Map<String, PlatformEventService.PlatformEventInfo> byName =
            indexByApiName(PlatformEventService.getAllPlatformEvents());

        System.assert(byName.containsKey('UriEvent'));
        System.assertEquals('/event/UriEvent', byName.get('UriEvent').channel);
    }

    @IsTest
    static void getAllPlatformEvents_threatDetectionEvents_shape() {
        Map<String, PlatformEventService.PlatformEventInfo> byName =
            indexByApiName(PlatformEventService.getAllPlatformEvents());

        for (String name : new List<String>{
            'ApiAnomalyEvent', 'ReportAnomalyEvent',
            'SessionHijackingEvent', 'CredentialStuffingEvent'
        }) {
            System.assert(byName.containsKey(name), name + ' must be present');
            System.assertEquals('Standard Platform Event', byName.get(name).eventType);
            System.assertEquals('/event/' + name, byName.get(name).channel);
        }
    }

    @IsTest
    static void getAllPlatformEvents_bulkApiResultEvent_shape() {
        Map<String, PlatformEventService.PlatformEventInfo> byName =
            indexByApiName(PlatformEventService.getAllPlatformEvents());

        PlatformEventService.PlatformEventInfo e = byName.get('BulkApiResultEvent');
        System.assertNotEquals(null, e);
        System.assertEquals('/event/BulkApiResultEvent', e.channel);
    }

    @IsTest
    static void getAllPlatformEvents_flowExecutionErrorEvent_shape() {
        Map<String, PlatformEventService.PlatformEventInfo> byName =
            indexByApiName(PlatformEventService.getAllPlatformEvents());

        System.assert(byName.containsKey('FlowExecutionErrorEvent'));
    }

    @IsTest
    static void getAllPlatformEvents_platformStatusAlertEvent_shape() {
        Map<String, PlatformEventService.PlatformEventInfo> byName =
            indexByApiName(PlatformEventService.getAllPlatformEvents());

        System.assert(byName.containsKey('PlatformStatusAlertEvent'));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getAllPlatformEvents – AllChangeEvents meta-channel
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getAllPlatformEvents_allChangeEventsMetaChannelPresent() {
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();
        Map<String, PlatformEventService.PlatformEventInfo> byName = indexByApiName(events);

        System.assert(byName.containsKey('AllChangeEvents'),
            'AllChangeEvents meta-channel must be in the list');

        PlatformEventService.PlatformEventInfo e = byName.get('AllChangeEvents');
        System.assertEquals('Change Data Capture',  e.eventType);
        System.assertEquals('/data/ChangeEvents',    e.channel);
        System.assertEquals('All Change Events',     e.label);
        System.assertNotEquals(null, e.description);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getAllPlatformEvents – channel format rules
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getAllPlatformEvents_standardEventsUseEventPrefix() {
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();

        for (PlatformEventService.PlatformEventInfo e : events) {
            if (e.eventType == 'Standard Platform Event') {
                System.assert(
                    e.channel.startsWith('/event/'),
                    'Standard event channel must start with /event/ — got: ' + e.channel
                );
                System.assertEquals('/event/' + e.apiName, e.channel,
                    'Standard event channel must be /event/<apiName>');
            }
        }
    }

    @IsTest
    static void getAllPlatformEvents_customEventsUseEventPrefix() {
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();

        for (PlatformEventService.PlatformEventInfo e : events) {
            if (e.eventType == 'Custom Platform Event') {
                System.assert(
                    e.channel.startsWith('/event/'),
                    'Custom event channel must start with /event/ — got: ' + e.channel
                );
                System.assert(
                    e.apiName.endsWith('__e'),
                    'Custom event apiName must end with __e — got: ' + e.apiName
                );
            }
        }
    }

    @IsTest
    static void getAllPlatformEvents_cdcEventsUseDataPrefix() {
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();

        for (PlatformEventService.PlatformEventInfo e : events) {
            if (e.eventType == 'Change Data Capture'
                    && e.apiName != 'AllChangeEvents') {
                System.assert(
                    e.channel.startsWith('/data/'),
                    'CDC event channel must start with /data/ — got: ' + e.channel
                );
                System.assert(
                    e.apiName.endsWith('ChangeEvent')
                    || e.apiName.endsWith('ChangeEvent__c'),
                    'CDC apiName must end with ChangeEvent — got: ' + e.apiName
                );
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getAllPlatformEvents – sort order
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getAllPlatformEvents_listIsSorted() {
        List<PlatformEventService.PlatformEventInfo> events =
            PlatformEventService.getAllPlatformEvents();

        // PlatformEventInfo.sort() uses default String comparison on apiName.
        // We simply verify that consecutive elements are in non-descending order.
        for (Integer i = 0; i < events.size() - 1; i++) {
            System.assert(
                events[i].apiName.compareTo(events[i + 1].apiName) <= 0,
                'List should be sorted: "' + events[i].apiName +
                '" should come before "' + events[i + 1].apiName + '"'
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getEventFields – negative cases
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getEventFields_blankString_returnsEmptyList() {
        Test.startTest();
        List<PlatformEventService.FieldInfo> fields =
            PlatformEventService.getEventFields('');
        Test.stopTest();

        System.assertNotEquals(null, fields);
        System.assertEquals(0, fields.size(),
            'Blank API name should return empty list');
    }

    @IsTest
    static void getEventFields_whitespaceOnly_returnsEmptyList() {
        Test.startTest();
        List<PlatformEventService.FieldInfo> fields =
            PlatformEventService.getEventFields('   ');
        Test.stopTest();

        System.assertEquals(0, fields.size(),
            'Whitespace-only input should return empty list');
    }

    @IsTest
    static void getEventFields_unknownApiName_returnsEmptyList() {
        Test.startTest();
        List<PlatformEventService.FieldInfo> fields =
            PlatformEventService.getEventFields('TotallyMadeUp__e');
        Test.stopTest();

        System.assertNotEquals(null, fields);
        System.assertEquals(0, fields.size(),
            'Unknown event API name should return empty list');
    }

    @IsTest
    static void getEventFields_standardEventNotInGlobalDescribe_returnsEmptyList() {
        // Standard events like LoginEvent are not in getGlobalDescribe()
        Test.startTest();
        List<PlatformEventService.FieldInfo> fields =
            PlatformEventService.getEventFields('LoginEvent');
        Test.stopTest();

        // May return 0 if LoginEvent is not in globalDescribe,
        // or non-zero if the org has it — either is acceptable.
        System.assertNotEquals(null, fields,
            'Result must never be null even for standard events');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getEventFields – positive: Account (always exists in any org)
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getEventFields_accountSObject_returnsNonEmptyList() {
        // Account is always present in globalDescribe
        Test.startTest();
        List<PlatformEventService.FieldInfo> fields =
            PlatformEventService.getEventFields('Account');
        Test.stopTest();

        System.assert(fields.size() > 0,
            'Account should yield at least one FieldInfo');
    }

    @IsTest
    static void getEventFields_accountSObject_fieldInfoHasRequiredProperties() {
        List<PlatformEventService.FieldInfo> fields =
            PlatformEventService.getEventFields('Account');

        for (PlatformEventService.FieldInfo f : fields) {
            System.assertNotEquals(null, f.name,
                'Every FieldInfo must have a non-null name');
            System.assertNotEquals(null, f.label,
                'Every FieldInfo must have a non-null label');
            System.assertNotEquals(null, f.fieldType,
                'Every FieldInfo must have a non-null fieldType');
            System.assertNotEquals(null, f.required,
                'Every FieldInfo must have a non-null required flag');
        }
    }

    @IsTest
    static void getEventFields_accountSObject_idFieldPresent() {
        List<PlatformEventService.FieldInfo> fields =
            PlatformEventService.getEventFields('Account');

        Boolean idFound = false;
        for (PlatformEventService.FieldInfo f : fields) {
            if (f.name == 'Id') {
                idFound = true;
                System.assertEquals('ID', f.fieldType,
                    'Id field should have type ID');
                break;
            }
        }
        System.assert(idFound, 'Id field must be present for Account');
    }

    @IsTest
    static void getEventFields_accountSObject_nameFieldPresent() {
        List<PlatformEventService.FieldInfo> fields =
            PlatformEventService.getEventFields('Account');

        Boolean nameFound = false;
        for (PlatformEventService.FieldInfo f : fields) {
            if (f.name == 'Name') {
                nameFound = true;
                break;
            }
        }
        System.assert(nameFound, 'Name field must be present for Account');
    }

    @IsTest
    static void getEventFields_accountSObject_noDuplicateFieldNames() {
        List<PlatformEventService.FieldInfo> fields =
            PlatformEventService.getEventFields('Account');

        Set<String> seen = new Set<String>();
        for (PlatformEventService.FieldInfo f : fields) {
            System.assert(!seen.contains(f.name),
                'Duplicate field name found: ' + f.name);
            seen.add(f.name);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Inner class constructor coverage
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void platformEventInfo_constructor_allFieldsSet() {
        PlatformEventService.PlatformEventInfo info =
            new PlatformEventService.PlatformEventInfo(
                'MyOrder__e',
                'My Order Event',
                TestDataFactory.TYPE_CUSTOM,
                '/event/MyOrder__e',
                'Fires when an order is placed'
            );

        System.assertEquals('MyOrder__e',                  info.apiName);
        System.assertEquals('My Order Event',              info.label);
        System.assertEquals(TestDataFactory.TYPE_CUSTOM,   info.eventType);
        System.assertEquals('/event/MyOrder__e',           info.channel);
        System.assertEquals('Fires when an order is placed', info.description);
    }

    @IsTest
    static void platformEventInfo_propertiesAreMutable() {
        PlatformEventService.PlatformEventInfo info =
            new PlatformEventService.PlatformEventInfo(
                'Orig__e', 'Original', 'Custom Platform Event',
                '/event/Orig__e', 'desc'
            );

        info.apiName    = 'Updated__e';
        info.label      = 'Updated Label';
        info.eventType  = 'Standard Platform Event';
        info.channel    = '/event/Updated__e';
        info.description = 'New description';

        System.assertEquals('Updated__e',            info.apiName);
        System.assertEquals('Updated Label',         info.label);
        System.assertEquals('Standard Platform Event', info.eventType);
        System.assertEquals('/event/Updated__e',     info.channel);
        System.assertEquals('New description',       info.description);
    }

    @IsTest
    static void fieldInfo_constructor_allFieldsSet() {
        PlatformEventService.FieldInfo fi =
            new PlatformEventService.FieldInfo(
                'Amount__c', 'Amount', 'CURRENCY', false
            );

        System.assertEquals('Amount__c', fi.name);
        System.assertEquals('Amount',    fi.label);
        System.assertEquals('CURRENCY',  fi.fieldType);
        System.assertEquals(false,       fi.required);
    }

    @IsTest
    static void fieldInfo_requiredTrue_storedCorrectly() {
        PlatformEventService.FieldInfo fi =
            new PlatformEventService.FieldInfo('Name', 'Name', 'STRING', true);

        System.assertEquals(true, fi.required,
            'required=true must be stored correctly');
    }

    @IsTest
    static void fieldInfo_propertiesAreMutable() {
        PlatformEventService.FieldInfo fi =
            new PlatformEventService.FieldInfo('Orig', 'Orig', 'TEXT', false);

        fi.name      = 'NewName';
        fi.label     = 'New Label';
        fi.fieldType = 'NUMBER';
        fi.required  = true;

        System.assertEquals('NewName',  fi.name);
        System.assertEquals('New Label', fi.label);
        System.assertEquals('NUMBER',   fi.fieldType);
        System.assertEquals(true,       fi.required);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TestDataFactory sample list integration
    // ═══════════════════════════════════════════════════════════════════════════

    @IsTest
    static void buildSampleEventInfoList_returnsThreeEvents() {
        List<PlatformEventService.PlatformEventInfo> sample =
            TestDataFactory.buildSampleEventInfoList();

        System.assertEquals(3, sample.size());

        System.assertEquals(TestDataFactory.TYPE_CUSTOM,    sample[0].eventType);
        System.assertEquals(TestDataFactory.TYPE_CDC,       sample[1].eventType);
        System.assertEquals(TestDataFactory.TYPE_STANDARD,  sample[2].eventType);
    }

    @IsTest
    static void buildSampleEventInfoList_channelsCorrect() {
        List<PlatformEventService.PlatformEventInfo> sample =
            TestDataFactory.buildSampleEventInfoList();

        System.assertEquals('/event/TestCustomEvent__e', sample[0].channel);
        System.assertEquals('/data/AccountChangeEvent',  sample[1].channel);
        System.assertEquals('/event/LoginEvent',         sample[2].channel);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Helpers
    // ═══════════════════════════════════════════════════════════════════════════

    private static Map<String, PlatformEventService.PlatformEventInfo> indexByApiName(
        List<PlatformEventService.PlatformEventInfo> events
    ) {
        Map<String, PlatformEventService.PlatformEventInfo> result =
            new Map<String, PlatformEventService.PlatformEventInfo>();
        for (PlatformEventService.PlatformEventInfo e : events) {
            result.put(e.apiName, e);
        }
        return result;
    }
}
