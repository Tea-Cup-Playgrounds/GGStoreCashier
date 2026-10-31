const { uuidv7 } = require('../utils/uuid');

// Records who changed what. `db` can be the pool or a connection inside a transaction, so the
// log entry commits or rolls back together with the change it describes.
const logAudit = async (db, req, { action, entity, entityId = null, locationId = null, before = null, after = null }) => {
    await db.execute(
        `INSERT INTO audit_logs (id, user_id, device_id, location_id, action, entity, entity_id, \`before\`, \`after\`, ip)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
            uuidv7(),
            req.user ? req.user.id : null,
            req.deviceId || null,
            locationId,
            action,
            entity,
            entityId === null ? null : String(entityId),
            before === null ? null : JSON.stringify(before),
            after === null ? null : JSON.stringify(after),
            req.ip || null,
        ]
    );
};

module.exports = { logAudit };
