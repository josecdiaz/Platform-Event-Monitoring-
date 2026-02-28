import { LightningElement, api, track } from 'lwc';
import {
    subscribe,
    unsubscribe,
    onError,
    isEmpEnabled
} from 'lightning/empApi';

/**
 * platformEventSubscriber
 *
 * Headless LWC that wraps the lightning/empApi to manage one subscription.
 * Parent components control it via @api methods and listen for custom events.
 *
 * Custom events fired:
 *   - 'eventreceived'  : { detail: { message, channel } }
 *   - 'subscribed'     : { detail: { channel } }
 *   - 'unsubscribed'   : { detail: { channel } }
 *   - 'subscribeerror' : { detail: { channel, error } }
 *   - 'statuschange'   : { detail: { empEnabled: Boolean } }
 */
export default class PlatformEventSubscriber extends LightningElement {

    @api channel  = '';   // e.g. /event/MyEvent__e
    @api replayId = -1;   // -1 = tip, -2 = all retained events

    @track _subscription = null;
    @track _isSubscribed = false;

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        // Register a global error handler for EMP API
        onError(error => {
            console.error('[PlatformEventSubscriber] EMP API error:', JSON.stringify(error));
            this.dispatchEvent(new CustomEvent('subscribeerror', {
                detail: { channel: this.channel, error: JSON.stringify(error) },
                bubbles: true,
                composed: true
            }));
        });

        // Check EMP API availability
        isEmpEnabled()
            .then(enabled => {
                this.dispatchEvent(new CustomEvent('statuschange', {
                    detail: { empEnabled: enabled },
                    bubbles: true,
                    composed: true
                }));
            })
            .catch(err => console.warn('[PlatformEventSubscriber] isEmpEnabled error:', err));
    }

    disconnectedCallback() {
        if (this._subscription) {
            unsubscribe(this._subscription).catch(() => {});
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    @api
    get isSubscribed() {
        return this._isSubscribed;
    }

    @api
    async subscribeToChannel() {
        if (!this.channel) {
            console.warn('[PlatformEventSubscriber] No channel specified');
            return;
        }
        if (this._isSubscribed) {
            return;
        }

        try {
            const replayId = this.replayId != null ? Number(this.replayId) : -1;
            this._subscription = await subscribe(
                this.channel,
                replayId,
                (message) => this._handleMessage(message)
            );
            this._isSubscribed = true;
            this.dispatchEvent(new CustomEvent('subscribed', {
                detail: { channel: this.channel },
                bubbles: true,
                composed: true
            }));
        } catch (err) {
            console.error('[PlatformEventSubscriber] Subscribe error:', err);
            this.dispatchEvent(new CustomEvent('subscribeerror', {
                detail: { channel: this.channel, error: err.message || String(err) },
                bubbles: true,
                composed: true
            }));
        }
    }

    @api
    async unsubscribeFromChannel() {
        if (!this._subscription) return;
        try {
            await unsubscribe(this._subscription);
            this._subscription = null;
            this._isSubscribed = false;
            this.dispatchEvent(new CustomEvent('unsubscribed', {
                detail: { channel: this.channel },
                bubbles: true,
                composed: true
            }));
        } catch (err) {
            console.error('[PlatformEventSubscriber] Unsubscribe error:', err);
        }
    }

    // ── Private ───────────────────────────────────────────────────────────────

    _handleMessage(message) {
        this.dispatchEvent(new CustomEvent('eventreceived', {
            detail: { message, channel: this.channel },
            bubbles: true,
            composed: true
        }));
    }
}
