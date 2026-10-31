/**
 * Development / UAT accounts:
 *   superadmin                 owner (every location)
 *   admin1..3, kasir1..3       branch manager and cashier at Cabang 1..3 (BR01..BR03)
 *   gudang                     warehouse staff at the main warehouse (WH)
 *   akuntan                    accountant (every location)
 *
 * Every account gets the same password (SEED_PASSWORD, default Password#123). Missing branches and
 * the warehouse are created. Safe to run again: existing users keep their name, get the password
 * reset, are re-activated, and their assignments are replaced with the ones below.
 *
 *   npm run seed
 *
 * Refuses to run with NODE_ENV=production unless ALLOW_DEV_SEED=true: these are known passwords.
 */
const bcrypt = require('bcrypt');

const PASSWORD = process.env.SEED_PASSWORD || 'Password#123';

const BRANCHES = [
    { code: 'BR01', name: 'Cabang 1', word: 'Satu' },
    { code: 'BR02', name: 'Cabang 2', word: 'Dua' },
    { code: 'BR03', name: 'Cabang 3', word: 'Tiga' },
];

// [username, name, role code, location code or null for every location]
// Names avoid digits: the user API only accepts letters, spaces, - ' and . in names.
const ACCOUNTS = [
    ['superadmin', 'Super Admin', 'owner', null],
    ...BRANCHES.flatMap((b, i) => [
        [`admin${i + 1}`, `Admin Cabang ${b.word}`, 'branch_manager', b.code],
        [`kasir${i + 1}`, `Kasir Cabang ${b.word}`, 'cashier', b.code],
    ]),
    ['gudang', 'Staf Gudang', 'warehouse', 'WH'],
    ['akuntan', 'Akuntan', 'accountant', null],
];

exports.seed = async function (knex) {
    if (process.env.NODE_ENV === 'production' && process.env.ALLOW_DEV_SEED !== 'true') {
        throw new Error('01_dev_accounts: refusing to create accounts with a known password in production (set ALLOW_DEV_SEED=true to override)');
    }
    const hash = await bcrypt.hash(PASSWORD, 12);

    await knex.transaction(async (trx) => {
        // ── locations ──
        const locationIds = {};
        const [[warehouse]] = await trx.raw("SELECT id FROM locations WHERE code = 'WH'");
        locationIds.WH = warehouse
            ? warehouse.id
            : (await trx('locations').insert({ code: 'WH', name: 'Gudang Utama', type: 'warehouse' }))[0];
        for (const b of BRANCHES) {
            const [[existing]] = await trx.raw('SELECT id FROM locations WHERE code = ?', [b.code]);
            locationIds[b.code] = existing ? existing.id : (await trx('locations').insert({ code: b.code, name: b.name, type: 'branch' }))[0];
        }

        // ── users ──
        const roles = Object.fromEntries((await trx('roles').select('id', 'code')).map((r) => [r.code, r.id]));
        for (const [username, name, roleCode, locationCode] of ACCOUNTS) {
            if (!roles[roleCode]) throw new Error(`Role "${roleCode}" is missing; run npm run migrate first`);
            const [[user]] = await trx.raw('SELECT id FROM users WHERE username = ?', [username]);
            const userId = user
                ? user.id
                : (await trx('users').insert({ name, username, password: hash, is_active: 1 }))[0];
            if (user) await trx('users').where({ id: userId }).update({ password: hash, is_active: 1 });

            await trx('user_locations').where({ user_id: userId }).delete();
            await trx('user_locations').insert({
                user_id: userId,
                location_id: locationCode ? locationIds[locationCode] : null,
                role_id: roles[roleCode],
            });
        }
    });

    console.log(`01_dev_accounts: ${ACCOUNTS.length} akun siap (${ACCOUNTS.map((a) => a[0]).join(', ')})`);
};
