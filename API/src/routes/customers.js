const express = require('express');
const pool = require('../db');
const { authenticateToken } = require('../middleware/auth');
const { logAudit } = require('../services/audit');
const { AppError, withTransaction } = require('../utils/transaction');
const { uuidv7 } = require('../utils/uuid');

// Customers are shared by all locations. Cashiers look them up by phone at the counter.
const router = express.Router();

router.use(authenticateToken);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Anyone who sells may find and register customers; editing needs customers.manage.
const requireCustomerAccess = (req, res, next) => {
    if (req.access.can('customers.manage') || req.access.can('sales.create')) return next();
    return res.status(403).json({ error: 'Akses tidak diizinkan' });
};

// Indonesian mobile numbers: "+62 812-3456-789", "62812..." and "0812..." are the same number.
const normalizePhone = (value) => {
    if (value === undefined || value === null) return null;
    let digits = String(value).replace(/\D/g, '');
    if (digits.startsWith('62')) digits = `0${digits.slice(2)}`;
    return digits === '' ? null : digits;
};

const readCustomer = (body, { partial }) => {
    const fields = {};
    if (!partial || body.name !== undefined) {
        const name = typeof body.name === 'string' ? body.name.trim() : '';
        if (name.length < 2 || name.length > 150) throw new AppError('Nama pelanggan 2–150 karakter');
        fields.name = name;
    }
    if (body.phone !== undefined) {
        const phone = normalizePhone(body.phone);
        if (phone !== null && !/^0\d{8,14}$/.test(phone)) throw new AppError('Nomor telepon tidak valid');
        fields.phone = phone;
    }
    for (const [key, max] of [['email', 100], ['address', 1000], ['id_number', 30], ['notes', 2000], ['code', 30]]) {
        if (body[key] === undefined) continue;
        const value = body[key] === null ? '' : String(body[key]).trim();
        if (value.length > max) throw new AppError(`${key} terlalu panjang`);
        fields[key] = value || null;
    }
    return fields;
};

const duplicatePhone = async (db, phone, exceptId) => {
    if (!phone) return null;
    const [[row]] = await db.execute('SELECT id, name, phone FROM customers WHERE phone = ? AND id <> ? AND deleted_at IS NULL', [phone, exceptId || '']);
    return row || null;
};

// Inserts a customer and returns it. Used by POST /api/customers and by sales that register a
// customer inline. An existing customer with the same phone is returned instead of a duplicate.
const createCustomer = async (conn, req, body) => {
    const fields = readCustomer(body, { partial: false });
    const existing = await duplicatePhone(conn, fields.phone);
    if (existing) return { customer: existing, created: false };

    const id = body.id && UUID.test(String(body.id)) ? String(body.id).toLowerCase() : uuidv7();
    const columns = ['id', ...Object.keys(fields)];
    try {
        await conn.execute(
            `INSERT INTO customers (${columns.join(', ')}) VALUES (${columns.map(() => '?').join(', ')})`,
            [id, ...Object.keys(fields).map((k) => fields[k])]
        );
    } catch (error) {
        if (error.code === 'ER_DUP_ENTRY') throw new AppError('Data pelanggan duplikat (kode atau ID sudah ada)', 409);
        throw error;
    }
    await logAudit(conn, req, { action: 'create', entity: 'customer', entityId: id, after: fields });
    const [[customer]] = await conn.execute('SELECT * FROM customers WHERE id = ?', [id]);
    return { customer, created: true };
};

// GET /api/customers?search=  (name, phone or code)
router.get('/', requireCustomerAccess, async (req, res) => {
    try {
        const search = String(req.query.search || '').trim();
        let query = 'SELECT id, code, name, phone, email, address, created_at, updated_at FROM customers WHERE deleted_at IS NULL';
        const params = [];
        if (search) {
            const phone = normalizePhone(search);
            query += ' AND (name LIKE ? OR code = ?' + (phone ? ' OR phone LIKE ?' : '') + ')';
            params.push(`%${search}%`, search);
            if (phone) params.push(`${phone}%`);
        }
        query += ' ORDER BY updated_at DESC LIMIT 50';
        const [customers] = await pool.execute(query, params);
        res.json({ customers });
    } catch (error) {
        console.error('Get customers error:', error);
        res.status(500).json({ error: 'Gagal mengambil data pelanggan' });
    }
});

// Customer with their purchases and the IMEI units they bought (for warranty lookups).
router.get('/:id', requireCustomerAccess, async (req, res) => {
    try {
        const [[customer]] = await pool.execute('SELECT * FROM customers WHERE id = ? AND deleted_at IS NULL', [req.params.id]);
        if (!customer) return res.status(404).json({ error: 'Pelanggan tidak ditemukan' });
        const [sales] = await pool.execute(
            `SELECT s.id, s.number, s.occurred_at, s.grand_total, s.refunded_total, s.status, l.code AS location_code
             FROM sales s JOIN locations l ON l.id = s.location_id
             WHERE s.customer_id = ? ORDER BY s.occurred_at DESC LIMIT 100`,
            [customer.id]
        );
        const [units] = await pool.execute(
            `SELECT u.id AS unit_id, u.imei1, u.imei2, u.serial_number, u.status, sl.description,
                    DATE_FORMAT(sl.warranty_until, '%Y-%m-%d') AS warranty_until, s.number AS sale_number, s.occurred_at
             FROM sale_lines sl JOIN sales s ON s.id = sl.sale_id JOIN product_units u ON u.id = sl.unit_id
             WHERE s.customer_id = ? AND s.status <> 'voided' ORDER BY s.occurred_at DESC`,
            [customer.id]
        );
        res.json({ customer, sales, units });
    } catch (error) {
        console.error('Get customer error:', error);
        res.status(500).json({ error: 'Gagal mengambil data pelanggan' });
    }
});

// Body: { id?, name, phone, email, address, id_number, notes }. id may come from the device.
// 200 with the existing customer when the phone is already registered, 201 when created.
router.post('/', requireCustomerAccess, async (req, res) => {
    const result = await withTransaction(res, 'Gagal menyimpan pelanggan', (conn) => createCustomer(conn, req, req.body));
    if (result) res.status(result.created ? 201 : 200).json({ message: result.created ? 'Pelanggan ditambahkan' : 'Pelanggan dengan nomor ini sudah terdaftar', ...result });
});

router.put('/:id', async (req, res) => {
    if (!req.access.can('customers.manage')) return res.status(403).json({ error: 'Akses tidak diizinkan' });
    const result = await withTransaction(res, 'Gagal memperbarui pelanggan', async (conn) => {
        const [[before]] = await conn.execute('SELECT * FROM customers WHERE id = ? AND deleted_at IS NULL FOR UPDATE', [req.params.id]);
        if (!before) throw new AppError('Pelanggan tidak ditemukan', 404);
        const fields = readCustomer(req.body, { partial: true });
        if (Object.keys(fields).length === 0) throw new AppError('Tidak ada field yang valid untuk diperbarui');
        const duplicate = await duplicatePhone(conn, fields.phone, before.id);
        if (duplicate) throw new AppError(`Nomor ${fields.phone} sudah dipakai ${duplicate.name}`, 409);
        const columns = Object.keys(fields);
        await conn.execute(`UPDATE customers SET ${columns.map((c) => `${c} = ?`).join(', ')} WHERE id = ?`, [...columns.map((c) => fields[c]), before.id]);
        await logAudit(conn, req, { action: 'update', entity: 'customer', entityId: before.id, before, after: fields });
        const [[customer]] = await conn.execute('SELECT * FROM customers WHERE id = ?', [before.id]);
        return customer;
    });
    if (result) res.json({ message: 'Pelanggan diperbarui', customer: result });
});

module.exports = router;
module.exports.createCustomer = createCustomer;
