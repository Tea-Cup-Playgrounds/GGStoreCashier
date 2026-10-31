const { uuidv7 } = require('../utils/uuid');
const { AppError } = require('../utils/transaction');

// The only code that changes stock. Every function here must be called with a connection that
// is inside a transaction; each change locks the affected rows and writes its stock_movements
// row in that same transaction, so the ledger always matches stock_levels / product_units.
//
// ctx = { userId, deviceId } — who is making the change.

class StockError extends AppError {}

const toMoney = (value) => Math.round(Number(value) * 100) / 100;

// ── identifiers ─────────────────────────────────────────────────────────────

// IMEIs are 15 digits; the last one is a Luhn check digit, which catches most typos.
const isValidImei = (imei) => {
    if (!/^\d{15}$/.test(imei)) return false;
    let sum = 0;
    for (let i = 0; i < 15; i++) {
        let digit = Number(imei[14 - i]);
        if (i % 2 === 1) {
            digit *= 2;
            if (digit > 9) digit -= 9;
        }
        sum += digit;
    }
    return sum % 10 === 0;
};

const SERIAL = /^[A-Za-z0-9\-\/]{3,50}$/;

const normalizeIdentifier = (value) => {
    if (value === undefined || value === null) return null;
    const trimmed = String(value).replace(/\s+/g, '');
    return trimmed === '' ? null : trimmed;
};

// Validates a unit's identifiers against the product's serial_type. With requireComplete=false
// (warehouse receiving), identifiers may be left empty and filled in before the unit is sold.
const validateIdentifiers = (serialType, { imei1, imei2, serial_number }, { requireComplete }) => {
    for (const [label, imei] of [['IMEI 1', imei1], ['IMEI 2', imei2]]) {
        if (imei !== null && !isValidImei(imei)) {
            throw new StockError(`${label} "${imei}" tidak valid (harus 15 digit dengan check digit yang benar)`);
        }
    }
    if (imei1 !== null && imei1 === imei2) throw new StockError('IMEI 1 dan IMEI 2 tidak boleh sama');
    if (serial_number !== null && !SERIAL.test(serial_number)) {
        throw new StockError(`Nomor seri "${serial_number}" tidak valid (3–50 karakter: huruf, angka, - atau /)`);
    }
    if (serialType !== 'imei_dual' && imei2 !== null) throw new StockError('Produk ini hanya memiliki satu IMEI');

    if (requireComplete) {
        if ((serialType === 'imei' || serialType === 'imei_dual') && imei1 === null) throw new StockError('IMEI wajib diisi');
        if (serialType === 'imei_dual' && imei2 === null) throw new StockError('IMEI 2 wajib diisi untuk produk dual SIM');
        if (serialType === 'serial' && serial_number === null) throw new StockError('Nomor seri wajib diisi');
    }
};

// IMEI 1 and IMEI 2 share one namespace: a number may not appear in either column of another unit.
const assertIdentifiersUnused = async (conn, { imei1, imei2, serial_number }, exceptUnitId = null) => {
    const imeis = [imei1, imei2].filter(Boolean);
    if (imeis.length > 0) {
        const marks = imeis.map(() => '?').join(', ');
        const [rows] = await conn.execute(
            `SELECT imei1, imei2 FROM product_units
             WHERE (imei1 IN (${marks}) OR imei2 IN (${marks})) AND id <> ?`,
            [...imeis, ...imeis, exceptUnitId || '']
        );
        if (rows.length > 0) {
            const taken = imeis.find((i) => rows.some((r) => r.imei1 === i || r.imei2 === i));
            throw new StockError(`IMEI ${taken} sudah terdaftar`, 409);
        }
    }
    if (serial_number) {
        const [rows] = await conn.execute(
            'SELECT id FROM product_units WHERE serial_number = ? AND id <> ?',
            [serial_number, exceptUnitId || '']
        );
        if (rows.length > 0) throw new StockError(`Nomor seri ${serial_number} sudah terdaftar`, 409);
    }
};

// ── helpers ─────────────────────────────────────────────────────────────────

const getVariant = async (conn, variantId) => {
    const [rows] = await conn.execute(
        `SELECT v.id, v.product_id, v.is_active, v.deleted_at, p.kind, p.is_serialized, p.serial_type,
                p.is_active AS product_active, p.deleted_at AS product_deleted_at
         FROM product_variants v JOIN products p ON p.id = v.product_id
         WHERE v.id = ?`,
        [variantId]
    );
    if (rows.length === 0) throw new StockError(`Varian ${variantId} tidak ditemukan`, 404);
    const variant = rows[0];
    if (variant.kind !== 'goods') throw new StockError('Produk jasa/digital tidak memiliki stok');
    return variant;
};

const assertLocation = async (conn, locationId) => {
    const [rows] = await conn.execute(
        'SELECT id FROM locations WHERE id = ? AND is_active = 1 AND deleted_at IS NULL',
        [locationId]
    );
    if (rows.length === 0) throw new StockError(`Lokasi ${locationId} tidak ditemukan atau tidak aktif`, 404);
};

// Locks (creating if needed) the stock_levels row for a variant at a location.
const lockLevel = async (conn, locationId, variantId) => {
    await conn.execute(
        'INSERT IGNORE INTO stock_levels (location_id, variant_id, qty, avg_cost) VALUES (?, ?, 0, 0)',
        [locationId, variantId]
    );
    const [[level]] = await conn.execute(
        'SELECT qty, avg_cost FROM stock_levels WHERE location_id = ? AND variant_id = ? FOR UPDATE',
        [locationId, variantId]
    );
    return { qty: Number(level.qty), avgCost: Number(level.avg_cost) };
};

const writeMovement = async (conn, ctx, m) => {
    const id = uuidv7();
    await conn.execute(
        `INSERT INTO stock_movements
            (id, location_id, variant_id, unit_id, qty_change, unit_cost, reason, ref_type, ref_id, user_id, device_id, note)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
            id, m.locationId, m.variantId, m.unitId || null, m.qtyChange, toMoney(m.unitCost || 0), m.reason,
            m.refType || null, m.refId === undefined || m.refId === null ? null : String(m.refId),
            ctx.userId || null, ctx.deviceId || null, m.note || null,
        ]
    );
    return id;
};

// ── non-serialized stock ────────────────────────────────────────────────────

// Changes the quantity of a non-serialized variant at a location.
// - Incoming stock with a unitCost updates the moving-average cost.
// - Outgoing stock is valued at the current average cost.
// - Stock may not go below zero unless allowNegative (used later for offline sales that already happened).
// Returns { qty, avgCost, movementId, unitCost }.
const adjustQuantity = async (conn, ctx, {
    locationId, variantId, qtyChange, unitCost, reason, refType, refId, note, allowNegative = false,
}) => {
    if (!Number.isInteger(qtyChange) || qtyChange === 0) throw new StockError('Jumlah perubahan stok harus bilangan bulat selain 0');

    const variant = await getVariant(conn, variantId);
    if (variant.is_serialized) throw new StockError('Produk ber-IMEI/serial diubah per unit, bukan per jumlah');
    await assertLocation(conn, locationId);

    const level = await lockLevel(conn, locationId, variantId);
    const newQty = level.qty + qtyChange;
    if (newQty < 0 && !allowNegative) {
        throw new StockError(`Stok tidak mencukupi. Tersedia: ${level.qty}, diminta: ${-qtyChange}`);
    }

    let avgCost = level.avgCost;
    let movementCost = level.avgCost;
    if (qtyChange > 0 && unitCost !== undefined && unitCost !== null) {
        const cost = Number(unitCost);
        if (!Number.isFinite(cost) || cost < 0) throw new StockError('Harga pokok tidak valid');
        movementCost = cost;
        avgCost = level.qty > 0 ? (level.qty * level.avgCost + qtyChange * cost) / newQty : cost;
    }
    avgCost = toMoney(avgCost);

    await conn.execute(
        'UPDATE stock_levels SET qty = ?, avg_cost = ? WHERE location_id = ? AND variant_id = ?',
        [newQty, avgCost, locationId, variantId]
    );
    const movementId = await writeMovement(conn, ctx, {
        locationId, variantId, qtyChange, unitCost: movementCost, reason, refType, refId, note,
    });

    return { qty: newQty, avgCost, movementId, unitCost: toMoney(movementCost) };
};

// ── serialized units ────────────────────────────────────────────────────────

// Brings new units into stock at a location (one +1 movement each).
// units: [{ imei1, imei2, serial_number, unit_cost, condition_grade, sell_price, notes }]
// requireIdentifiers=false lets the warehouse receive units now and register IMEIs later.
const receiveUnits = async (conn, ctx, {
    locationId, variantId, units, reason = 'adjustment', sourceType = 'adjustment', sourceId = null,
    refType, refId, note, requireIdentifiers = true,
}) => {
    if (!Array.isArray(units) || units.length === 0) throw new StockError('Daftar unit wajib diisi');
    if (units.length > 500) throw new StockError('Maksimal 500 unit per permintaan');

    const variant = await getVariant(conn, variantId);
    if (!variant.is_serialized) throw new StockError('Produk ini tidak menggunakan IMEI/serial; ubah stok per jumlah');
    await assertLocation(conn, locationId);
    await lockLevel(conn, locationId, variantId); // marks the variant as stocked here

    const seen = new Set();
    const created = [];
    for (const input of units) {
        const ids = {
            imei1: normalizeIdentifier(input.imei1),
            imei2: normalizeIdentifier(input.imei2),
            serial_number: normalizeIdentifier(input.serial_number),
        };
        validateIdentifiers(variant.serial_type, ids, { requireComplete: requireIdentifiers });
        for (const value of Object.values(ids).filter(Boolean)) {
            if (seen.has(value)) throw new StockError(`IMEI/serial ${value} muncul lebih dari sekali`);
            seen.add(value);
        }
        await assertIdentifiersUnused(conn, ids);

        const unitCost = toMoney(input.unit_cost || 0);
        if (!Number.isFinite(unitCost) || unitCost < 0) throw new StockError('Harga pokok unit tidak valid');
        const grade = input.condition_grade || 'new';
        if (!['new', 'A', 'B', 'C'].includes(grade)) throw new StockError('Kondisi unit harus new, A, B, atau C');
        const sellPrice = input.sell_price === undefined || input.sell_price === null || input.sell_price === '' ? null : toMoney(input.sell_price);

        const id = uuidv7();
        await conn.execute(
            `INSERT INTO product_units
                (id, variant_id, location_id, imei1, imei2, serial_number, status, condition_grade,
                 unit_cost, sell_price, source_type, source_id, notes)
             VALUES (?, ?, ?, ?, ?, ?, 'in_stock', ?, ?, ?, ?, ?, ?)`,
            [id, variantId, locationId, ids.imei1, ids.imei2, ids.serial_number, grade,
                unitCost, sellPrice, sourceType, sourceId, input.notes || null]
        );
        await writeMovement(conn, ctx, {
            locationId, variantId, unitId: id, qtyChange: 1, unitCost, reason, refType, refId, note,
        });
        created.push({ id, ...ids, unit_cost: unitCost, condition_grade: grade, sell_price: sellPrice });
    }
    return created;
};

const lockUnit = async (conn, unitId) => {
    const [rows] = await conn.execute(
        `SELECT u.*, p.serial_type FROM product_units u
         JOIN product_variants v ON v.id = u.variant_id
         JOIN products p ON p.id = v.product_id
         WHERE u.id = ? FOR UPDATE`,
        [unitId]
    );
    if (rows.length === 0) throw new StockError('Unit tidak ditemukan', 404);
    return rows[0];
};

// Fills in or corrects identifiers / grade / price on a unit. Only units still at a location
// can be edited; identifiers of sold units are part of the sale record.
const updateUnit = async (conn, unitId, changes) => {
    const unit = await lockUnit(conn, unitId);
    if (!['in_stock', 'reserved', 'defective'].includes(unit.status)) {
        throw new StockError('Hanya unit yang masih ada di stok yang dapat diubah');
    }

    const ids = {
        imei1: changes.imei1 !== undefined ? normalizeIdentifier(changes.imei1) : unit.imei1,
        imei2: changes.imei2 !== undefined ? normalizeIdentifier(changes.imei2) : unit.imei2,
        serial_number: changes.serial_number !== undefined ? normalizeIdentifier(changes.serial_number) : unit.serial_number,
    };
    validateIdentifiers(unit.serial_type, ids, { requireComplete: false });
    await assertIdentifiersUnused(conn, ids, unitId);

    const grade = changes.condition_grade !== undefined ? changes.condition_grade : unit.condition_grade;
    if (!['new', 'A', 'B', 'C'].includes(grade)) throw new StockError('Kondisi unit harus new, A, B, atau C');
    const sellPrice = changes.sell_price === undefined ? unit.sell_price
        : (changes.sell_price === null || changes.sell_price === '' ? null : toMoney(changes.sell_price));
    const notes = changes.notes !== undefined ? changes.notes || null : unit.notes;

    await conn.execute(
        `UPDATE product_units SET imei1 = ?, imei2 = ?, serial_number = ?, condition_grade = ?, sell_price = ?, notes = ?
         WHERE id = ?`,
        [ids.imei1, ids.imei2, ids.serial_number, grade, sellPrice, notes, unitId]
    );
    return { before: unit, after: { ...unit, ...ids, condition_grade: grade, sell_price: sellPrice, notes } };
};

// Takes one unit out of stock (-1 movement). status: 'sold' | 'written_off' | 'defective'.
// Sold and written-off units leave the location; defective units stay there, unsellable.
// A sale requires complete identifiers so the warranty can be traced.
const removeUnit = async (conn, ctx, { unitId, status, reason, refType, refId, note, expectedLocationId, saleLineId }) => {
    const unit = await lockUnit(conn, unitId);
    if (unit.status !== 'in_stock') throw new StockError(`Unit tidak tersedia (status: ${unit.status})`, 409);
    if (expectedLocationId !== undefined && unit.location_id !== Number(expectedLocationId)) {
        throw new StockError('Unit tidak berada di lokasi ini', 409);
    }
    if (status === 'sold') {
        validateIdentifiers(unit.serial_type, unit, { requireComplete: true });
    }

    const newLocation = status === 'defective' ? unit.location_id : null;
    await conn.execute(
        'UPDATE product_units SET status = ?, location_id = ?, sold_sale_line_id = ? WHERE id = ?',
        [status, newLocation, saleLineId || null, unitId]
    );
    await writeMovement(conn, ctx, {
        locationId: unit.location_id, variantId: unit.variant_id, unitId, qtyChange: -1,
        unitCost: unit.unit_cost, reason, refType, refId, note,
    });
    return unit;
};

// A sold unit coming back (void or customer return). Restocked units return to stock with a
// +1 movement; defective ones are kept at the location as 'defective' without a movement, since
// they never count as on-hand stock.
const returnSoldUnit = async (conn, ctx, { unitId, locationId, defective = false, refType, refId, note }) => {
    const unit = await lockUnit(conn, unitId);
    if (unit.status !== 'sold') throw new StockError(`Unit ${unit.imei1 || unit.serial_number || unitId} tidak berstatus terjual`, 409);
    await assertLocation(conn, locationId);
    await lockLevel(conn, locationId, unit.variant_id);

    await conn.execute(
        'UPDATE product_units SET status = ?, location_id = ?, sold_sale_line_id = NULL, warranty_until = NULL WHERE id = ?',
        [defective ? 'defective' : 'in_stock', locationId, unitId]
    );
    if (!defective) {
        await writeMovement(conn, ctx, {
            locationId, variantId: unit.variant_id, unitId, qtyChange: 1,
            unitCost: unit.unit_cost, reason: 'sale_return', refType, refId, note,
        });
    }
    return unit;
};

// ── transfers ───────────────────────────────────────────────────────────────

// Sends a unit out of its location: in_stock -> in_transit (no location), -1 movement at the source.
const shipUnit = async (conn, ctx, { unitId, fromLocationId, refType, refId, note }) => {
    const unit = await lockUnit(conn, unitId);
    if (unit.status !== 'in_stock') throw new StockError(`Unit ${unit.imei1 || unit.serial_number || unitId} tidak tersedia (status: ${unit.status})`, 409);
    if (unit.location_id !== Number(fromLocationId)) throw new StockError(`Unit ${unit.imei1 || unit.serial_number || unitId} tidak berada di lokasi asal`, 409);

    await conn.execute("UPDATE product_units SET status = 'in_transit', location_id = NULL WHERE id = ?", [unitId]);
    await writeMovement(conn, ctx, {
        locationId: unit.location_id, variantId: unit.variant_id, unitId, qtyChange: -1,
        unitCost: unit.unit_cost, reason: 'transfer_out', refType, refId, note,
    });
    return unit;
};

// Brings an in-transit unit into a location: in_transit -> in_stock, +1 movement there.
// Used when a transfer is received, and when an undelivered unit is returned to its source.
const landUnit = async (conn, ctx, { unitId, locationId, refType, refId, note }) => {
    const unit = await lockUnit(conn, unitId);
    if (unit.status !== 'in_transit') throw new StockError(`Unit ${unit.imei1 || unit.serial_number || unitId} tidak sedang dalam pengiriman`, 409);
    await assertLocation(conn, locationId);
    await lockLevel(conn, locationId, unit.variant_id);

    await conn.execute("UPDATE product_units SET status = 'in_stock', location_id = ? WHERE id = ?", [locationId, unitId]);
    await writeMovement(conn, ctx, {
        locationId, variantId: unit.variant_id, unitId, qtyChange: 1,
        unitCost: unit.unit_cost, reason: 'transfer_in', refType, refId, note,
    });
    return unit;
};

// A unit lost in transit. It already left its source's ledger when shipped, so no movement.
const writeOffInTransitUnit = async (conn, { unitId }) => {
    const unit = await lockUnit(conn, unitId);
    if (unit.status !== 'in_transit') throw new StockError('Unit tidak sedang dalam pengiriman', 409);
    await conn.execute("UPDATE product_units SET status = 'written_off' WHERE id = ?", [unitId]);
    return unit;
};

// ── per-location pricing ────────────────────────────────────────────────────

// sellPrice null removes the override (the variant's base_price applies again).
const setLocationPrice = async (conn, { locationId, variantId, sellPrice }) => {
    await getVariant(conn, variantId);
    await assertLocation(conn, locationId);
    await lockLevel(conn, locationId, variantId);
    const price = sellPrice === null ? null : toMoney(sellPrice);
    if (price !== null && (!Number.isFinite(price) || price < 0)) throw new StockError('Harga jual tidak valid');
    await conn.execute(
        'UPDATE stock_levels SET sell_price = ? WHERE location_id = ? AND variant_id = ?',
        [price, locationId, variantId]
    );
    return price;
};

module.exports = {
    StockError,
    isValidImei,
    adjustQuantity,
    receiveUnits,
    updateUnit,
    removeUnit,
    returnSoldUnit,
    shipUnit,
    landUnit,
    writeOffInTransitUnit,
    setLocationPrice,
    getVariant,
    normalizeIdentifier,
};
