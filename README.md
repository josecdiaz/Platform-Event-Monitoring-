# Platform Event Monitoring App for Salesforce

A comprehensive Salesforce application to discover, subscribe to, and monitor all Platform Events in your org — including Custom Platform Events, Change Data Capture (CDC) events, and Standard Salesforce Platform Events.

## Features

- **Event Discovery** — Automatically lists every platform event type available in your org
- **Filtering** — Filter events by type (Custom / CDC / Standard) or search by name
- **Real-time Subscriptions** — Subscribe to any event channel using the EMP/Streaming API
- **Persistent Logging** — Every received event is stored as a `Platform_Event_Log__c` record
- **Three Record Types** — Different page layouts for Standard Events, CDC Events, and Custom Events
- **JSON Payload Viewer** — Custom LWC that renders the event payload as a collapsible/expandable JSON tree with syntax highlighting

## Project Structure

```
force-app/main/default/
├── classes/                        Apex controllers and services
│   ├── PlatformEventService        Discovers platform events via Schema API
│   └── PlatformEventLogController  CRUD for Platform_Event_Log__c
├── lwc/
│   ├── platformEventMonitor        Main monitoring dashboard
│   ├── jsonViewer                  Recursive collapsible JSON tree component
│   └── platformEventSubscriber     EMP API subscription manager
├── objects/
│   └── Platform_Event_Log__c/      Custom object with 3 record types and 16 fields
├── layouts/                        Record type-specific page layouts
├── flexipages/                     Lightning App Builder pages
├── applications/                   Lightning App definition
├── permissionSets/                 Permission set for app users
└── tabs/                           Custom object tab
```

## Object: Platform_Event_Log__c

| Field | Type | Description |
|-------|------|-------------|
| Event_UUID__c | Text (External ID) | Unique identifier for each event |
| Event_API_Name__c | Text | API name (e.g. MyEvent__e) |
| Event_Type__c | Picklist | Standard / CDC / Custom |
| Channel__c | Text | Subscription channel path |
| Replay_ID__c | Text | CometD replay ID |
| Published_By_ID__c | Text | User/system that published the event |
| Event_Published_Date__c | DateTime | When the event was published |
| Payload__c | Long Text | Raw JSON payload (full content) |
| Header_Data__c | Long Text | Full CometD message envelope JSON |
| Schema_ID__c | Text | Avro schema identifier |
| Subscription_Status__c | Picklist | Received / Processed / Error |
| Error_Message__c | Long Text | Processing error details |
| Entity_Name__c | Text | CDC: SObject entity type |
| Change_Type__c | Picklist | CDC: CREATE / UPDATE / DELETE / UNDELETE |
| Changed_Fields__c | Long Text | CDC: Comma-separated list of changed fields |
| Commit_Timestamp__c | Number | CDC: Transaction commit timestamp |

### Record Types

| Record Type | Purpose | Key Fields Highlighted |
|-------------|---------|----------------------|
| Standard_Platform_Event | Standard Salesforce events (LoginEvent, ApiEvent) | Channel, Replay ID, Published By, Header Data, Payload |
| Change_Data_Capture | CDC events (AccountChangeEvent) | Entity Name, Change Type, Changed Fields, Commit Timestamp |
| Custom_Platform_Event | User-defined __e events | Event API Name, Payload, Subscription Status, Error Message |

## Quick Start

### Prerequisites
- Salesforce CLI (sf) v2+
- An active Salesforce org (Developer Edition or scratch org)

### Deploy to Scratch Org

```bash
# Authenticate to Dev Hub
sf org login web --set-default-dev-hub

# Create scratch org
sf org create scratch -f config/project-scratch-def.json \
  -a PlatformEventMonitor --duration-days 30

# Deploy source
sf project deploy start

# Assign permission set
sf org assign permset --name Platform_Event_Monitor

# Open the org
sf org open
```

### Deploy to Existing Org

```bash
# Authenticate
sf org login web -a MyOrg

# Deploy
sf project deploy start -o MyOrg
```

## Usage

1. Open **Platform Event Monitor** from the App Launcher
2. Browse all available platform event types in your org
3. Use the **Search** bar or **Type** dropdown to filter events
4. Click **Subscribe** on any event to start receiving real-time data
5. Incoming events appear in the **Live Events** panel below
6. Click any event payload to open the interactive JSON tree viewer
7. All events are automatically saved as **Platform Event Log** records
8. View records in the **Platform Event Logs** tab with record-type-specific layouts

## LWC: jsonViewer

A reusable Lightning Web Component for rendering any JSON as an interactive tree.

- Collapsible/expandable object and array nodes
- Syntax highlighting by type (string, number, boolean, null)
- Preview of collapsed node contents
- Recursive rendering with depth-based indentation
- Expand-all / Collapse-all controls

```html
<c-json-viewer value={myJsonString}></c-json-viewer>
```

## Security

- All Apex classes use `with sharing`
- Permission set grants minimum required access
- No stored credentials or tokens
