/**
 * Fixed assets for the monthly recap's "Aset" row (Rekap Bulanan → Alokasi uang).
 *
 *   1-2000 Aset Tetap                      (group, not postable)
 *   1-2100 Peralatan & Inventaris Toko     etalase, komputer, printer, mesin servis
 *   1-2200 Renovasi & Bangunan             renovasi toko, partisi, instalasi
 *
 * Buying one is a manual journal (Dr 1-2xxx / Cr Bank or Kas). The recap counts what was put into
 * 1-2xxx accounts during the month. More asset accounts can be added under 1-2000 in Bagan Akun.
 */
const ACCOUNTS = [
    ['1-2000', 'Aset Tetap', '1-0000', 0],
    ['1-2100', 'Peralatan & Inventaris Toko', '1-2000', 1],
    ['1-2200', 'Renovasi & Bangunan', '1-2000', 1],
];

exports.up = async function (knex) {
    for (const [code, name, parentCode, postable] of ACCOUNTS) {
        const [[existing]] = await knex.raw('SELECT id FROM accounts WHERE code = ?', [code]);
        if (existing) continue;
        const [[parent]] = await knex.raw('SELECT id FROM accounts WHERE code = ?', [parentCode]);
        await knex.raw(
            "INSERT INTO accounts (code, name, type, parent_id, is_postable, is_system) VALUES (?, ?, 'asset', ?, ?, 1)",
            [code, name, parent ? parent.id : null, postable]
        );
    }
};

exports.down = async function (knex) {
    const [[used]] = await knex.raw(
        "SELECT COUNT(*) AS n FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id WHERE a.code LIKE '1-2%'"
    );
    if (Number(used.n) > 0) throw new Error('Akun aset tetap sudah dipakai di jurnal; tidak bisa di-rollback.');
    for (const [code] of [...ACCOUNTS].reverse()) await knex.raw('DELETE FROM accounts WHERE code = ?', [code]);
};
