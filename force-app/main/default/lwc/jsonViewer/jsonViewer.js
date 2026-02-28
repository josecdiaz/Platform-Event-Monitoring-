import { LightningElement, api, track } from 'lwc';

/**
 * jsonViewer
 *
 * A recursive LWC that renders any JSON value as a collapsible/expandable tree.
 *
 * Usage:
 *   <c-json-viewer value={myJsonStringOrObject}></c-json-viewer>
 *
 * @api value   - JSON string OR any JS value (object, array, primitive, null)
 * @api depth   - Internal: current nesting depth (auto-incremented by recursion)
 */
export default class JsonViewer extends LightningElement {

    // ── Public API ────────────────────────────────────────────────────────────

    @api depth = 0;

    _rawValue;
    _parsed;

    @api
    get value() {
        return this._rawValue;
    }

    set value(val) {
        this._rawValue = val;
        this._parsed   = this._parse(val);
        // Auto-expand first two levels for readability
        this._isExpanded = (this.depth || 0) < 2;
    }

    // ── Internal state ────────────────────────────────────────────────────────

    @track _isExpanded = true;

    // ── Type helpers ──────────────────────────────────────────────────────────

    get _type() {
        const v = this._parsed;
        if (v === null || v === undefined) return 'null';
        if (Array.isArray(v))             return 'array';
        return typeof v;                 // 'object' | 'string' | 'number' | 'boolean'
    }

    get isComplex()   { return this._type === 'object' || this._type === 'array'; }
    get isPrimitive() { return !this.isComplex; }
    get isExpanded()  { return this._isExpanded; }
    get isCollapsed() { return !this._isExpanded; }

    // ── Computed props for the template ──────────────────────────────────────

    get containerClass() {
        const d = this.depth || 0;
        return `jv-node jv-depth-${Math.min(d, 10)}`;
    }

    get primitiveClass() {
        const base = 'jv-primitive jv-type-';
        switch (this._type) {
            case 'string':  return base + 'string';
            case 'number':  return base + 'number';
            case 'boolean': return base + 'boolean';
            default:        return base + 'null';
        }
    }

    get displayValue() {
        const v = this._parsed;
        if (this._type === 'string')  return `"${v}"`;
        if (this._type === 'null')    return 'null';
        if (this._type === 'boolean') return String(v);
        return String(v);
    }

    get openBracket()  { return this._type === 'array' ? '[' : '{'; }
    get closeBracket() { return this._type === 'array' ? ']' : '}'; }

    get entries() {
        const v = this._parsed;
        if (this._type === 'object') {
            const keys = Object.keys(v);
            return keys.map((key, idx) => ({
                id:         `o-${this.depth}-${idx}-${key}`,
                displayKey: key,
                value:      v[key],
                showKey:    true,
                hasComma:   idx < keys.length - 1
            }));
        }
        if (this._type === 'array') {
            return v.map((item, idx) => ({
                id:         `a-${this.depth}-${idx}`,
                displayKey: String(idx),
                value:      item,
                showKey:    false,
                hasComma:   idx < v.length - 1
            }));
        }
        return [];
    }

    get childDepth() {
        return (this.depth || 0) + 1;
    }

    get collapsedPreview() {
        const v = this._parsed;
        if (this._type === 'array') {
            return v.length === 0 ? '' : `… ${v.length} item${v.length > 1 ? 's' : ''}`;
        }
        const keys = Object.keys(v);
        if (keys.length === 0) return '';
        const preview = keys.slice(0, 4).join(', ');
        return keys.length > 4 ? `${preview}, …` : preview;
    }

    get itemCountLabel() {
        const v = this._parsed;
        if (this._type === 'array') {
            return '';
        }
        const n = Object.keys(v).length;
        return `// ${n} key${n !== 1 ? 's' : ''}`;
    }

    get toggleTitle()   { return this._isExpanded ? 'Collapse' : 'Expand'; }
    get isExpandedStr() { return String(this._isExpanded); }

    get toggleIconClass() {
        return this._isExpanded ? 'jv-icon jv-icon-down' : 'jv-icon jv-icon-right';
    }

    // ── Event handlers ────────────────────────────────────────────────────────

    handleToggle() {
        this._isExpanded = !this._isExpanded;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _parse(val) {
        if (typeof val === 'string') {
            const trimmed = val.trim();
            if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
                (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
                try { return JSON.parse(trimmed); } catch (_) { /* fall through */ }
            }
        }
        return val === undefined ? null : val;
    }
}
