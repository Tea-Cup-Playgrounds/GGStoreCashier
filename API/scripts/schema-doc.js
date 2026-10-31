// Regenerates Database.md from the live schema (run after migrations):
//
//   npm run db:docs
//
// Table descriptions and grouping live below; columns, keys, foreign keys and views are read from
// information_schema, so the document always matches the database it was generated from.
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });
const fs = require('fs');
const path = require('path');
const pool = require('../src/db');

const GROUPS = [
    ['Organisasi & akses', {
        locations: 'Cabang dan gudang (kode BR01/WH dipakai di nomor dokumen).',
        users: 'Pengguna. Hak akses tidak disimpan di sini, tetapi di `user_locations`.',
        roles: 'Role (owner, branch_manager, cashier, warehouse, accountant, dan role kustom).',
        role_permissions: 'Izin per role; kunci izin didefinisikan di `API/src/auth/permissions.js`.',
        user_locations: 'Penugasan pengguna: role per lokasi (`location_id` NULL = semua lokasi).',
        devices: 'Perangkat kasir terdaftar.',
        audit_logs: 'Jejak audit perubahan penting (before/after).',
        settings: 'Pengaturan aplikasi (mis. harga termasuk PPN).',
        document_counters: 'Penomoran dokumen per lokasi per hari (GR-, TF-, SO-, INV-, RT-, JV-).',
    }],
    ['Katalog & stok', {
        categories: 'Kategori produk.',
        brands: 'Merek.',
        tax_rates: 'Tarif pajak (PPN 11%).',
        products: 'Produk (model), jenis goods/service/digital, serial/IMEI.',
        product_variants: 'Varian yang dijual (SKU, barcode, harga dasar).',
        stock_levels: 'Stok per varian per lokasi dengan harga pokok rata-rata dan harga lokasi.',
        product_units: 'Unit ber-IMEI/serial beserta status dan lokasinya.',
        stock_movements: 'Buku besar stok: setiap perubahan stok dicatat di sini.',
        stock_movements_legacy: 'Riwayat stok dari skema lama (arsip, tidak terhubung).',
        stock_on_hand: 'View: stok tersedia per varian per lokasi.',
    }],
    ['Pembelian, transfer, opname', {
        suppliers: 'Supplier.',
        goods_receipts: 'Penerimaan barang (GR-) dan statusnya.',
        goods_receipt_items: 'Baris penerimaan barang.',
        goods_receipt_units: 'Unit IMEI/serial yang diterima.',
        supplier_payments: 'Pembayaran ke supplier.',
        stock_transfers: 'Transfer stok antar lokasi (TF-).',
        stock_transfer_items: 'Baris transfer.',
        stock_transfer_units: 'Unit yang ditransfer.',
        stock_opnames: 'Stok opname (SO-).',
        stock_opname_items: 'Hitungan per varian.',
        stock_opname_units: 'Unit yang dipindai.',
        stock_opname_extras: 'Unit tak dikenal yang ditemukan saat opname.',
    }],
    ['Penjualan', {
        payment_methods: 'Metode pembayaran (Tunai, QRIS, E-Wallet, Kartu, Transfer).',
        customers: 'Pelanggan.',
        cash_sessions: 'Shift kasir (opsional) dengan kas awal dan selisih kas.',
        sales: 'Penjualan (INV-), termasuk data lama dengan nomor LEGACY-.',
        sale_lines: 'Baris penjualan.',
        sale_payments: 'Pembayaran per penjualan (split payment).',
        sale_returns: 'Retur penjualan (RT-).',
        sale_return_lines: 'Baris retur.',
        vouchers: 'Voucher diskon.',
    }],
    ['Akuntansi', {
        accounts: 'Bagan akun.',
        account_mappings: 'Akun yang dipakai tiap aturan posting otomatis.',
        accounting_periods: 'Periode akuntansi (tutup/buka bulan).',
        journal_entries: 'Jurnal (tidak pernah diubah; dibatalkan dengan jurnal balik).',
        journal_lines: 'Baris debit/kredit jurnal.',
    }],
    ['Lainnya', {
        absensi: 'Absensi karyawan (ditinjau ulang bersama payroll).',
        knex_migrations: 'Riwayat migrasi (knex).',
        knex_migrations_lock: 'Kunci migrasi (knex).',
    }],
];

(async () => {
    try {
        const [[{ db }]] = await pool.query('SELECT DATABASE() AS db');
        const [tables] = await pool.query(
            'SELECT table_name AS name, table_type AS type FROM information_schema.tables WHERE table_schema = ? ORDER BY table_name',
            [db]
        );
        const [columns] = await pool.query(
            `SELECT table_name AS t, column_name AS name, column_type AS type, is_nullable AS nullable,
                    column_default AS def, column_key AS k, extra AS extra
             FROM information_schema.columns WHERE table_schema = ? ORDER BY table_name, ordinal_position`,
            [db]
        );
        const [fks] = await pool.query(
            `SELECT k.table_name AS t, k.column_name AS col, k.referenced_table_name AS ref, k.referenced_column_name AS refcol,
                    r.delete_rule AS del
             FROM information_schema.key_column_usage k
             JOIN information_schema.referential_constraints r
               ON r.constraint_schema = k.constraint_schema AND r.constraint_name = k.constraint_name
             WHERE k.table_schema = ? AND k.referenced_table_name IS NOT NULL
             ORDER BY k.table_name, k.column_name`,
            [db]
        );

        const known = new Map(GROUPS.flatMap(([, entries]) => Object.entries(entries)));
        const existing = new Map(tables.map((t) => [t.name, t.type]));
        const cell = (v) => String(v).replace(/\|/g, '\\|');

        const out = [];
        out.push('## Skema Database', '');
        out.push('Dihasilkan dari skema database dengan `npm run db:docs` (setelah `npm run migrate`). Jangan diedit manual;');
        out.push('ubah deskripsi tabel di `API/scripts/schema-doc.js`. Rancangan lengkap: `docs/foundation-design.md`.', '');
        out.push('Hak akses: setiap pengguna punya penugasan di `user_locations` (role per lokasi). Tidak ada lagi');
        out.push('`users.role` / `users.branch_id` atau view `branches` (dihapus di langkah 6).', '');

        const groups = GROUPS.map(([title, entries]) => [title, Object.keys(entries).filter((t) => existing.has(t))]);
        const unknown = [...existing.keys()].filter((t) => !known.has(t));
        if (unknown.length) groups.push(['Belum dideskripsikan', unknown]);

        for (const [title, names] of groups) {
            if (names.length === 0) continue;
            out.push(`### ${title}`, '', '| Tabel | Deskripsi |', '| --- | --- |');
            for (const t of names) out.push(`| \`${t}\`${existing.get(t) === 'VIEW' ? ' (view)' : ''} | ${known.get(t) || ''} |`);
            out.push('');
        }

        out.push('---', '', '## Kolom per tabel', '');
        for (const [, names] of groups) {
            for (const t of names) {
                out.push(`### \`${t}\`${existing.get(t) === 'VIEW' ? ' (view)' : ''}`, '');
                out.push('| Kolom | Tipe | Null | Default | Kunci |', '| --- | --- | --- | --- | --- |');
                for (const c of columns.filter((c) => c.t === t)) {
                    const key = [c.k === 'PRI' ? 'PK' : c.k === 'UNI' ? 'UNIQUE' : c.k === 'MUL' ? 'index' : '', c.extra.includes('auto_increment') ? 'auto' : '']
                        .filter(Boolean).join(', ');
                    out.push(`| ${c.name} | ${cell(c.type)} | ${c.nullable === 'YES' ? 'ya' : ''} | ${c.def === null ? '' : cell(c.def)} | ${key} |`);
                }
                const refs = fks.filter((f) => f.t === t);
                if (refs.length) {
                    out.push('', 'Relasi: ' + refs.map((f) => `\`${f.col}\` → \`${f.ref}.${f.refcol}\`${f.del === 'CASCADE' ? ' (cascade)' : ''}`).join(', '));
                }
                out.push('');
            }
        }

        const file = path.resolve(__dirname, '../../Database.md');
        fs.writeFileSync(file, out.join('\n'));
        console.log(`Database.md ditulis dari database "${db}" (${existing.size} tabel/view).`);
    } finally {
        await pool.end();
    }
})().catch((error) => {
    console.error(error);
    process.exit(1);
});
