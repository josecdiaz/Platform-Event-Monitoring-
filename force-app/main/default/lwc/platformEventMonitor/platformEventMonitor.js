import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAllPlatformEvents from '@salesforce/apex/PlatformEventService.getAllPlatformEvents';
import createEventLog     from '@salesforce/apex/PlatformEventLogController.createEventLog';
import clearLogsForChannel from '@salesforce/apex/PlatformEventLogController.clearLogsForChannel';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

const EVENT_TYPE_BADGE = {
    'Custom Platform Event' : 'pem-badge-custom',
    'Change Data Capture'   : 'pem-badge-cdc',
    'Standard Platform Event': 'pem-badge-standard'
};

function formatDate(isoString) {
    if (!isoString) return '';
    try {
        return new Date(isoString).toLocaleString();
    } catch (_) { return isoString; }
}

function safeParseJson(str) {
    if (!str) return null;
    if (typeof str === 'object') return str;
    try { return JSON.parse(str); } catch (_) { return str; }
}

// ─────────────────────────────────────────────────────────────────────────────
export default class PlatformEventMonitor extends NavigationMixin(LightningElement) {

    // ── State ─────────────────────────────────────────────────────────────────

    @track _allEvents       = [];
    @track filteredEvents   = [];
    @track searchTerm       = '';
    @track selectedType     = 'All';
    @track isLoading        = true;
    @track _error           = null;
    @track empUnavailable   = false;

    // Map: channel → { channel, apiName, eventType }
    @track _subscriptions   = {};

    // Map: channel → Array<eventObject>
    @track _liveEvents      = {};

    @track activeTab        = null;
    @track _payloadState    = {};   // eventId → { payload: bool, envelope: bool }

    // ── Options ───────────────────────────────────────────────────────────────

    typeOptions = [
        { label: 'All Types',                value: 'All' },
        { label: 'Custom Platform Events',   value: 'Custom Platform Event' },
        { label: 'Change Data Capture',      value: 'Change Data Capture' },
        { label: 'Standard Platform Events', value: 'Standard Platform Event' }
    ];

    // ── Wire ──────────────────────────────────────────────────────────────────

    @wire(getAllPlatformEvents)
    wiredEvents({ data, error }) {
        if (data) {
            this._allEvents = data.map(e => this._enrichEvent(e));
            this._applyFilters();
            this.isLoading = false;
        } else if (error) {
            this._error = error?.body?.message || 'Failed to load platform events.';
            this.isLoading = false;
        }
    }

    // ── Computed ──────────────────────────────────────────────────────────────

    get showTable()        { return !this.isLoading && !this._error; }
    get hasError()         { return !!this._error; }
    get errorMessage()     { return this._error; }
    get noResults()        { return !this.isLoading && this.filteredEvents.length === 0; }
    get filteredCount()    { return this.filteredEvents.length; }
    get totalCount()       { return this._allEvents.length; }
    get hasSubscriptions() { return Object.keys(this._subscriptions).length > 0; }

    get subscribedChannels() {
        return Object.values(this._subscriptions).map(sub => ({
            ...sub,
            eventCount : (this._liveEvents[sub.channel] || []).length,
            tabClass   : this._tabClass(sub.channel)
        }));
    }

    get subscriberComponents() {
        return Object.values(this._subscriptions).map(sub => ({
            ...sub,
            replayId: -1
        }));
    }

    get activeTabEvents() {
        const events = this._liveEvents[this.activeTab] || [];
        return events.map(e => ({
            ...e,
            payloadExpanded       : !!(this._payloadState[e.id] && this._payloadState[e.id].payload),
            envelopeExpanded      : !!(this._payloadState[e.id] && this._payloadState[e.id].envelope),
            payloadExpandedStr    : String(!!(this._payloadState[e.id] && this._payloadState[e.id].payload)),
            envelopeExpandedStr   : String(!!(this._payloadState[e.id] && this._payloadState[e.id].envelope)),
            payloadToggleIconClass : (this._payloadState[e.id] && this._payloadState[e.id].payload)
                ? 'pem-toggle-icon pem-icon-down' : 'pem-toggle-icon pem-icon-right',
            envelopeToggleIconClass: (this._payloadState[e.id] && this._payloadState[e.id].envelope)
                ? 'pem-toggle-icon pem-icon-down' : 'pem-toggle-icon pem-icon-right'
        }));
    }

    get noLiveEvents() {
        return (this._liveEvents[this.activeTab] || []).length === 0;
    }

    // ── Handlers: filters ─────────────────────────────────────────────────────

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
        this._applyFilters();
    }

    handleTypeChange(event) {
        this.selectedType = event.detail.value;
        this._applyFilters();
    }

    handleRefresh() {
        this.isLoading  = true;
        this._error     = null;
        // Wire will re-execute automatically when we reset the cache
        // Force re-evaluation by temporarily clearing
        this._allEvents = [];
        this.filteredEvents = [];
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            // After a tick the wire fires again
            this.isLoading = false;
        }, 500);
    }

    // ── Handlers: subscriptions ───────────────────────────────────────────────

    handleSubscribe(event) {
        const { channel, apiname: apiName, eventtype: eventType } =
            event.currentTarget.dataset;
        if (!channel || this._subscriptions[channel]) return;

        this._subscriptions = {
            ...this._subscriptions,
            [channel]: { channel, apiName, eventType }
        };
        this._liveEvents = { ...this._liveEvents, [channel]: [] };

        if (!this.activeTab) {
            this.activeTab = channel;
        }

        // After the subscriber component mounts it will auto-subscribe.
        // We call it explicitly after next render via a ref.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const subscribers = this.template.querySelectorAll('c-platform-event-subscriber');
            subscribers.forEach(sub => {
                if (sub.dataset.channel === channel) {
                    sub.subscribeToChannel();
                }
            });
        }, 100);
    }

    handleUnsubscribe(event) {
        const channel = event.currentTarget.dataset.channel;
        if (!channel) return;

        const subscribers = this.template.querySelectorAll('c-platform-event-subscriber');
        subscribers.forEach(sub => {
            if (sub.dataset.channel === channel) {
                sub.unsubscribeFromChannel();
            }
        });
    }

    handleSubscribeConfirmed(event) {
        const { channel } = event.detail;
        this._updateEventRowSubscription(channel, true);
        this._toast('Subscribed', `Listening on ${channel}`, 'success');
    }

    handleUnsubscribeConfirmed(event) {
        const { channel } = event.detail;
        const subs = { ...this._subscriptions };
        delete subs[channel];
        this._subscriptions = subs;
        this._updateEventRowSubscription(channel, false);

        if (this.activeTab === channel) {
            const channels = Object.keys(this._subscriptions);
            this.activeTab = channels.length > 0 ? channels[0] : null;
        }
    }

    handleSubscribeError(event) {
        const { channel, error } = event.detail;
        this._toast('Subscription Error', `${channel}: ${error}`, 'error');
    }

    // ── Handlers: live events ─────────────────────────────────────────────────

    handleEventReceived(event) {
        const { message, channel } = event.detail;
        const sub = this._subscriptions[channel];
        if (!sub) return;

        const data        = message.data || {};
        const payload     = data.payload || {};
        const cometEvent  = data.event   || {};
        const schema      = data.schema  || '';

        const eventId = `${Date.now()}-${Math.random()}`;
        const eventObj = {
            id              : eventId,
            receivedAt      : formatDate(new Date().toISOString()),
            replayId        : String(cometEvent.replayId || ''),
            publishedById   : payload.CreatedById || '',
            publishedDate   : payload.CreatedDate || null,
            payloadObject   : payload,
            fullMessage     : message,
            logRecordId     : null
        };

        // Prepend to live list (newest first), cap at 200 per channel
        const updated = [eventObj, ...(this._liveEvents[channel] || [])].slice(0, 200);
        this._liveEvents = { ...this._liveEvents, [channel]: updated };

        // Auto-expand payload by default
        this._payloadState = {
            ...this._payloadState,
            [eventId]: { payload: true, envelope: false }
        };

        // Update event count on the row
        this._allEvents = this._allEvents.map(e => {
            if (e.channel === channel) {
                const count = (e.eventCount || 0) + 1;
                return { ...e, eventCount: count, eventCountLabel: String(count) };
            }
            return e;
        });
        this._applyFilters();

        // Persist to Salesforce
        this._persistLog(message, channel, sub, payload, schema, cometEvent)
            .then(logId => {
                // Patch the log record ID onto the in-memory event
                this._liveEvents = {
                    ...this._liveEvents,
                    [channel]: (this._liveEvents[channel] || []).map(e =>
                        e.id === eventId ? { ...e, logRecordId: logId } : e
                    )
                };
            })
            .catch(err => console.error('[PlatformEventMonitor] persist error:', err));
    }

    // ── Handlers: UI ──────────────────────────────────────────────────────────

    handleTabSelect(event) {
        this.activeTab = event.currentTarget.dataset.channel;
    }

    handlePayloadToggle(event) {
        const id = event.currentTarget.dataset.eventId;
        const cur = this._payloadState[id] || {};
        this._payloadState = {
            ...this._payloadState,
            [id]: { ...cur, payload: !cur.payload }
        };
    }

    handleEnvelopeToggle(event) {
        const id = event.currentTarget.dataset.eventId;
        const cur = this._payloadState[id] || {};
        this._payloadState = {
            ...this._payloadState,
            [id]: { ...cur, envelope: !cur.envelope }
        };
    }

    handleOpenRecord(event) {
        const recordId = event.currentTarget.dataset.recordId;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    handleClearLogs() {
        if (!this.activeTab) return;
        clearLogsForChannel({ channel: this.activeTab })
            .then(count => {
                this._liveEvents = { ...this._liveEvents, [this.activeTab]: [] };
                this._toast('Cleared', `Deleted ${count} log records`, 'info');
            })
            .catch(err => this._toast('Error', err?.body?.message || 'Clear failed', 'error'));
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    _enrichEvent(e) {
        return {
            ...e,
            isSubscribed    : !!this._subscriptions[e.channel],
            eventCount      : 0,
            eventCountLabel : '0',
            typeBadgeClass  : EVENT_TYPE_BADGE[e.eventType] || '',
            rowClass        : 'pem-row'
        };
    }

    _applyFilters() {
        const term = (this.searchTerm || '').toLowerCase();
        const type = this.selectedType;
        this.filteredEvents = this._allEvents
            .filter(e => {
                const matchName = !term ||
                    e.apiName.toLowerCase().includes(term) ||
                    (e.label  || '').toLowerCase().includes(term);
                const matchType = type === 'All' || e.eventType === type;
                return matchName && matchType;
            })
            .map(e => ({
                ...e,
                isSubscribed  : !!this._subscriptions[e.channel],
                rowClass      : this._subscriptions[e.channel]
                    ? 'pem-row pem-row-subscribed' : 'pem-row'
            }));
    }

    _updateEventRowSubscription(channel, isSubscribed) {
        this._allEvents = this._allEvents.map(e =>
            e.channel === channel ? { ...e, isSubscribed } : e
        );
        this._applyFilters();
    }

    _tabClass(channel) {
        return channel === this.activeTab ? 'pem-tab pem-tab-active' : 'pem-tab';
    }

    async _persistLog(message, channel, sub, payload, schema, cometEvent) {
        const isArray   = Array.isArray;
        const cdcHeader = payload.ChangeEventHeader || null;

        return createEventLog({
            eventApiName  : sub.apiName,
            eventType     : sub.eventType,
            channel       : channel,
            payload       : JSON.stringify(payload),
            headerData    : JSON.stringify(message),
            replayId      : String(cometEvent.replayId || ''),
            publishedById : payload.CreatedById || null,
            publishedDate : payload.CreatedDate  || null,
            schemaId      : schema || null,
            entityName    : cdcHeader ? cdcHeader.entityName : null,
            changeType    : cdcHeader ? cdcHeader.changeType : null,
            changedFields : cdcHeader && isArray(cdcHeader.changedFields)
                ? cdcHeader.changedFields.join(',') : null,
            commitTimestamp : cdcHeader ? String(cdcHeader.commitTimestamp || '') : null
        });
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
