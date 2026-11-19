// Live updates: every change is announced to the devices that may show it, after it is saved.
//
// How it works
//   - Each request collects changes in req.liveChanges: logAudit() adds one for every audited
//     change, and queueChange() covers the few writes that are not audited (categories, vouchers,
//     stock-count scanning) or that matter to a second location (transfers).
//   - liveEvents(io) sends them when the response has finished with a success status. Routes commit
//     before they respond, so nothing is announced for work that was rolled back or refused.
//   - Event `changed` = { entity, action, ids, location_id, topics, at }. It says what changed, not
//     the new data: clients reload through the normal API, which applies permissions. `topics` tells
//     clients which screens care (see TOPICS), so they need no list of entities.
//   - Rooms: a change at a location goes to that location's room and to the all-locations room
//     (branch-0, owners/accountants). A change without a location (catalog, users, head office)
//     goes to every connected device.
//
// Delivery is best effort; clients reload everything on reconnect (see the app's SocketService).

const TOPICS = {
    sale: ['sales', 'stock', 'shifts', 'reports', 'accounting'],
    cash_session: ['shifts', 'reports', 'accounting'],
    customer: ['customers'],
    voucher: ['vouchers'],
    payment_method: ['settings'],
    stock: ['stock', 'catalog', 'accounting'],
    unit: ['stock'],
    product: ['catalog', 'stock'],
    variant: ['catalog', 'stock'],
    brand: ['catalog'],
    category: ['catalog'],
    tax_rate: ['catalog', 'settings'],
    goods_receipt: ['purchasing', 'stock', 'accounting', 'reports'],
    supplier: ['purchasing'],
    transfer: ['transfers', 'stock', 'accounting'],
    opname: ['opnames', 'stock', 'accounting'],
    expense: ['expenses', 'accounting', 'reports'],
    pulsa_deposit: ['pulsa', 'accounting', 'reports'],
    journal: ['accounting', 'reports'],
    opening_balance: ['accounting', 'reports'],
    account: ['accounting'],
    account_mapping: ['accounting'],
    period: ['accounting'],
    location: ['locations'],
    user: ['users', 'access'],
    user_assignments: ['users', 'access'],
    role: ['users', 'access'],
};

const topicsOf = (entity) => TOPICS[entity] || ['other'];

/** Announce a change once the request succeeds. `locationId` null = no location (everyone). */
const queueChange = (req, { entity, action, id = null, locationId = null }) => {
    if (!req || !Array.isArray(req.liveChanges)) return; // scripts, tests without the middleware
    req.liveChanges.push({
        entity,
        action,
        id: id === null || id === undefined ? null : String(id),
        locationId: locationId === undefined || locationId === null ? null : Number(locationId),
    });
};

/** One event per (entity, action, location); ids merged. */
const group = (changes) => {
    const byKey = new Map();
    for (const c of changes) {
        const key = `${c.entity}|${c.action}|${c.locationId}`;
        const entry = byKey.get(key) || { entity: c.entity, action: c.action, location_id: c.locationId, ids: [] };
        if (c.id !== null && !entry.ids.includes(c.id)) entry.ids.push(c.id);
        byKey.set(key, entry);
    }
    return [...byKey.values()];
};

const publish = (io, changes) => {
    const at = new Date().toISOString();
    for (const event of group(changes)) {
        const payload = { ...event, topics: topicsOf(event.entity), at };
        if (event.location_id === null) io.emit('changed', payload);
        else io.to(`branch-${event.location_id}`).to('branch-0').emit('changed', payload);
    }
};

/** Express middleware: collect changes per request, publish them after a successful response. */
const liveEvents = (io) => (req, res, next) => {
    req.liveChanges = [];
    res.on('finish', () => {
        if (res.statusCode >= 400 || req.liveChanges.length === 0) return;
        try {
            publish(io, req.liveChanges);
        } catch (error) {
            console.error('live events:', error.message);
        }
    });
    next();
};

module.exports = { liveEvents, queueChange, topicsOf, TOPICS };
