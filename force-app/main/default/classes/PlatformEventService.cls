/**
 * PlatformEventService
 *
 * Discovers all platform event types available in the org via the Schema API:
 *   - Custom Platform Events  : SObject names ending in __e
 *   - Change Data Capture     : SObject names ending in ChangeEvent
 *   - Standard Platform Events: Hardcoded list of Salesforce-delivered events
 *
 * Also exposes field-level metadata for any given event API name.
 */
public with sharing class PlatformEventService {

    // ──────────────────────────────────────────────────────────────────────────
    // Inner class representing a platform event type
    // ──────────────────────────────────────────────────────────────────────────
    public class PlatformEventInfo {
        @AuraEnabled public String apiName    { get; set; }
        @AuraEnabled public String label      { get; set; }
        @AuraEnabled public String eventType  { get; set; }
        @AuraEnabled public String channel    { get; set; }
        @AuraEnabled public String description{ get; set; }

        public PlatformEventInfo(String apiName, String label, String eventType,
                                  String channel, String description) {
            this.apiName     = apiName;
            this.label       = label;
            this.eventType   = eventType;
            this.channel     = channel;
            this.description = description;
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Inner class representing a single field descriptor
    // ──────────────────────────────────────────────────────────────────────────
    public class FieldInfo {
        @AuraEnabled public String name      { get; set; }
        @AuraEnabled public String label     { get; set; }
        @AuraEnabled public String fieldType { get; set; }
        @AuraEnabled public Boolean required { get; set; }

        public FieldInfo(String name, String label, String fieldType, Boolean required) {
            this.name      = name;
            this.label     = label;
            this.fieldType = fieldType;
            this.required  = required;
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Standard Salesforce-delivered platform events (not in getGlobalDescribe)
    // ──────────────────────────────────────────────────────────────────────────
    private static final List<Map<String, String>> STANDARD_EVENTS = new List<Map<String, String>>{
        newStdEvent('LoginEvent',               'Login Event',                'Security: user login attempts'),
        newStdEvent('LoginAsEvent',             'Login As Event',             'Security: admin login-as actions'),
        newStdEvent('LogoutEvent',              'Logout Event',               'Security: user logout'),
        newStdEvent('ApiEvent',                 'API Event',                  'API usage and REST/SOAP calls'),
        newStdEvent('UriEvent',                 'URI Event',                  'UI page navigation events'),
        newStdEvent('ApiAnomalyEvent',          'API Anomaly Event',          'Threat detection: unusual API patterns'),
        newStdEvent('ReportAnomalyEvent',       'Report Anomaly Event',       'Threat detection: unusual report access'),
        newStdEvent('SessionHijackingEvent',    'Session Hijacking Event',    'Threat detection: session hijacking'),
        newStdEvent('CredentialStuffingEvent',  'Credential Stuffing Event',  'Threat detection: credential stuffing'),
        newStdEvent('BulkApiResultEvent',       'Bulk API Result Event',      'Bulk API job completion notifications'),
        newStdEvent('FlowExecutionErrorEvent',  'Flow Execution Error Event', 'Flow runtime errors'),
        newStdEvent('PlatformStatusAlertEvent', 'Platform Status Alert Event','Salesforce service alerts')
    };

    private static Map<String, String> newStdEvent(String apiName, String label, String desc) {
        return new Map<String, String>{
            'apiName'  => apiName,
            'label'    => label,
            'desc'     => desc
        };
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Returns all platform events discoverable in this org
    // ──────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<PlatformEventInfo> getAllPlatformEvents() {
        List<PlatformEventInfo> events = new List<PlatformEventInfo>();

        // 1. Iterate global describe once and classify each SObject
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

        for (String name : gd.keySet()) {
            String nameLower = name.toLowerCase();

            if (nameLower.endsWith('__e')) {
                // Custom platform event
                Schema.DescribeSObjectResult d = gd.get(name).getDescribe();
                events.add(new PlatformEventInfo(
                    d.getName(),
                    d.getLabel(),
                    'Custom Platform Event',
                    '/event/' + d.getName(),
                    'Custom platform event defined in this org'
                ));
            } else if (nameLower.endsWith('changeevent')) {
                // Change Data Capture event
                Schema.DescribeSObjectResult d = gd.get(name).getDescribe();
                events.add(new PlatformEventInfo(
                    d.getName(),
                    d.getLabel(),
                    'Change Data Capture',
                    '/data/' + d.getName(),
                    'CDC event for ' + d.getLabel().replace(' Change Event', '')
                ));
            }
        }

        // 2. Add standard Salesforce-delivered events
        for (Map<String, String> se : STANDARD_EVENTS) {
            events.add(new PlatformEventInfo(
                se.get('apiName'),
                se.get('label'),
                'Standard Platform Event',
                '/event/' + se.get('apiName'),
                se.get('desc')
            ));
        }

        // 3. AllChangeEvents meta-channel
        events.add(new PlatformEventInfo(
            'AllChangeEvents',
            'All Change Events',
            'Change Data Capture',
            '/data/ChangeEvents',
            'Subscribe to all CDC events across all objects at once'
        ));

        events.sort();
        return events;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Returns field metadata for a given custom platform event API name
    // (only works for events present in getGlobalDescribe, i.e. custom + CDC)
    // ──────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getEventFields(String eventApiName) {
        List<FieldInfo> fields = new List<FieldInfo>();
        if (String.isBlank(eventApiName)) {
            return fields;
        }

        try {
            Schema.SObjectType sot = Schema.getGlobalDescribe().get(eventApiName);
            if (sot == null) {
                return fields;
            }
            Map<String, Schema.SObjectField> fieldMap = sot.getDescribe().fields.getMap();
            for (String fn : fieldMap.keySet()) {
                Schema.DescribeFieldResult fr = fieldMap.get(fn).getDescribe();
                fields.add(new FieldInfo(
                    fr.getName(),
                    fr.getLabel(),
                    String.valueOf(fr.getType()),
                    fr.isNillable() == false
                ));
            }
        } catch (Exception ex) {
            // Standard events are not in globalDescribe — return empty list gracefully
        }

        return fields;
    }
}
