## Skema Database

Dihasilkan dari skema database dengan `npm run db:docs` (setelah `npm run migrate`). Jangan diedit manual;
ubah deskripsi tabel di `API/scripts/schema-doc.js`. Rancangan lengkap: `docs/foundation-design.md`.

Hak akses: setiap pengguna punya penugasan di `user_locations` (role per lokasi). Tidak ada lagi
`users.role` / `users.branch_id` atau view `branches` (dihapus di langkah 6).

### Organisasi & akses

| Tabel | Deskripsi |
| --- | --- |
| `locations` | Cabang dan gudang (kode BR01/WH dipakai di nomor dokumen). |
| `users` | Pengguna. Hak akses tidak disimpan di sini, tetapi di `user_locations`. |
| `roles` | Role (owner, branch_manager, cashier, warehouse, accountant, dan role kustom). |
| `role_permissions` | Izin per role; kunci izin didefinisikan di `API/src/auth/permissions.js`. |
| `user_locations` | Penugasan pengguna: role per lokasi (`location_id` NULL = semua lokasi). |
| `devices` | Perangkat kasir terdaftar. |
| `audit_logs` | Jejak audit perubahan penting (before/after). |
| `settings` | Pengaturan aplikasi (mis. harga termasuk PPN). |
| `document_counters` | Penomoran dokumen per lokasi per hari (GR-, TF-, SO-, INV-, RT-, JV-). |

### Katalog & stok

| Tabel | Deskripsi |
| --- | --- |
| `categories` | Kategori produk. |
| `brands` | Merek. |
| `tax_rates` | Tarif pajak (PPN 11%). |
| `products` | Produk (model), jenis goods/service/digital, serial/IMEI. |
| `product_variants` | Varian yang dijual (SKU, barcode, harga dasar). |
| `stock_levels` | Stok per varian per lokasi dengan harga pokok rata-rata dan harga lokasi. |
| `product_units` | Unit ber-IMEI/serial beserta status dan lokasinya. |
| `stock_movements` | Buku besar stok: setiap perubahan stok dicatat di sini. |
| `stock_movements_legacy` | Riwayat stok dari skema lama (arsip, tidak terhubung). |
| `stock_on_hand` (view) | View: stok tersedia per varian per lokasi. |

### Pembelian, transfer, opname

| Tabel | Deskripsi |
| --- | --- |
| `suppliers` | Supplier. |
| `goods_receipts` | Penerimaan barang (GR-) dan statusnya. |
| `goods_receipt_items` | Baris penerimaan barang. |
| `goods_receipt_units` | Unit IMEI/serial yang diterima. |
| `supplier_payments` | Pembayaran ke supplier. |
| `stock_transfers` | Transfer stok antar lokasi (TF-). |
| `stock_transfer_items` | Baris transfer. |
| `stock_transfer_units` | Unit yang ditransfer. |
| `stock_opnames` | Stok opname (SO-). |
| `stock_opname_items` | Hitungan per varian. |
| `stock_opname_units` | Unit yang dipindai. |
| `stock_opname_extras` | Unit tak dikenal yang ditemukan saat opname. |

### Penjualan

| Tabel | Deskripsi |
| --- | --- |
| `payment_methods` | Metode pembayaran (Tunai, QRIS, E-Wallet, Kartu, Transfer). |
| `customers` | Pelanggan. |
| `cash_sessions` | Shift kasir (opsional) dengan kas awal dan selisih kas. |
| `sales` | Penjualan (INV-), termasuk data lama dengan nomor LEGACY-. |
| `sale_lines` | Baris penjualan. |
| `sale_payments` | Pembayaran per penjualan (split payment). |
| `sale_returns` | Retur penjualan (RT-). |
| `sale_return_lines` | Baris retur. |
| `vouchers` | Voucher diskon. |

### Akuntansi

| Tabel | Deskripsi |
| --- | --- |
| `accounts` | Bagan akun. |
| `account_mappings` | Akun yang dipakai tiap aturan posting otomatis. |
| `accounting_periods` | Periode akuntansi (tutup/buka bulan). |
| `journal_entries` | Jurnal (tidak pernah diubah; dibatalkan dengan jurnal balik). |
| `journal_lines` | Baris debit/kredit jurnal. |

### Lainnya

| Tabel | Deskripsi |
| --- | --- |
| `absensi` | Absensi karyawan (ditinjau ulang bersama payroll). |
| `knex_migrations` | Riwayat migrasi (knex). |
| `knex_migrations_lock` | Kunci migrasi (knex). |

---

## Kolom per tabel

### `locations`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| code | varchar(10) |  |  | UNIQUE |
| name | varchar(100) |  |  |  |
| address | text | ya |  |  |
| phone | varchar(20) | ya |  |  |
| type | enum('branch','warehouse') |  | branch |  |
| is_active | tinyint(1) |  | 1 |  |
| settings | json | ya |  |  |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime(3) | ya | CURRENT_TIMESTAMP(3) |  |
| deleted_at | datetime(3) | ya |  |  |

### `users`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| name | varchar(100) |  |  |  |
| username | varchar(100) |  |  |  |
| password | varchar(255) |  |  |  |
| pin_hash | varchar(255) | ya |  |  |
| is_active | tinyint(1) |  | 1 |  |
| last_active_at | datetime | ya |  |  |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime | ya | CURRENT_TIMESTAMP |  |

### `roles`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| code | varchar(30) | ya |  | UNIQUE |
| name | varchar(50) |  |  | UNIQUE |
| description | varchar(255) | ya |  |  |
| is_system | tinyint(1) |  | 0 |  |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime(3) | ya | CURRENT_TIMESTAMP(3) |  |

### `role_permissions`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| role_id | int |  |  | PK |
| permission | varchar(64) |  |  | PK |

Relasi: `role_id` → `roles.id` (cascade)

### `user_locations`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| user_id | int |  |  | index |
| location_id | int | ya |  | index |
| role_id | int |  |  | index |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |

Relasi: `location_id` → `locations.id` (cascade), `role_id` → `roles.id`, `user_id` → `users.id` (cascade)

### `devices`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| location_id | int |  |  | index |
| name | varchar(100) |  |  |  |
| platform | enum('android','ios','windows') |  |  |  |
| receipt_prefix | char(3) |  |  |  |
| registered_by | int | ya |  | index |
| last_sync_at | datetime(3) | ya |  |  |
| revoked_at | datetime(3) | ya |  |  |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime(3) | ya | CURRENT_TIMESTAMP(3) |  |

Relasi: `location_id` → `locations.id`, `registered_by` → `users.id`

### `audit_logs`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| user_id | int | ya |  | index |
| device_id | char(36) | ya |  |  |
| location_id | int | ya |  | index |
| action | varchar(50) |  |  |  |
| entity | varchar(50) |  |  | index |
| entity_id | varchar(36) | ya |  |  |
| before | json | ya |  |  |
| after | json | ya |  |  |
| ip | varchar(45) | ya |  |  |
| created_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

### `settings`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| key | varchar(64) |  |  | PK |
| value | json |  |  |  |
| updated_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

### `document_counters`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| prefix | varchar(10) |  |  | PK |
| location_id | int |  |  | PK |
| day | date |  |  | PK |
| last_seq | int |  | 0 |  |

### `categories`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| parent_id | int | ya |  | index |
| name | varchar(100) |  |  |  |
| description | text | ya |  |  |
| category_image | varchar(255) | ya |  |  |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime | ya | CURRENT_TIMESTAMP |  |

Relasi: `parent_id` → `categories.id`

### `brands`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| name | varchar(100) |  |  | UNIQUE |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime(3) | ya | CURRENT_TIMESTAMP(3) |  |
| deleted_at | datetime(3) | ya |  |  |

### `tax_rates`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| name | varchar(50) |  |  | UNIQUE |
| rate | decimal(5,2) |  |  |  |
| is_active | tinyint(1) |  | 1 |  |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime(3) | ya | CURRENT_TIMESTAMP(3) |  |

### `products`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| name | varchar(150) |  |  |  |
| description | text | ya |  |  |
| category_id | int | ya |  | index |
| brand_id | int | ya |  | index |
| kind | enum('goods','service','digital') |  | goods |  |
| is_serialized | tinyint(1) |  | 0 |  |
| serial_type | enum('imei','imei_dual','serial') | ya |  |  |
| warranty_months | smallint |  | 0 |  |
| tax_rate_id | int | ya |  | index |
| image | varchar(255) | ya |  |  |
| is_active | tinyint(1) |  | 1 |  |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime(3) | ya | CURRENT_TIMESTAMP(3) | index |
| deleted_at | datetime(3) | ya |  |  |

Relasi: `brand_id` → `brands.id`, `category_id` → `categories.id`, `tax_rate_id` → `tax_rates.id`

### `product_variants`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| product_id | int |  |  | index |
| sku | varchar(50) |  |  | UNIQUE |
| barcode | varchar(100) | ya |  | UNIQUE |
| name | varchar(100) | ya |  |  |
| attributes | json | ya |  |  |
| base_price | decimal(15,2) |  | 0.00 |  |
| min_price | decimal(15,2) | ya |  |  |
| is_active | tinyint(1) |  | 1 |  |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime(3) | ya | CURRENT_TIMESTAMP(3) | index |
| deleted_at | datetime(3) | ya |  |  |

Relasi: `product_id` → `products.id`

### `stock_levels`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| location_id | int |  |  | PK |
| variant_id | int |  |  | PK |
| qty | int |  | 0 |  |
| avg_cost | decimal(15,2) |  | 0.00 |  |
| sell_price | decimal(15,2) | ya |  |  |
| reorder_level | int | ya |  |  |
| updated_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

Relasi: `location_id` → `locations.id`, `variant_id` → `product_variants.id`

### `product_units`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| variant_id | int |  |  | index |
| location_id | int | ya |  | index |
| imei1 | varchar(20) | ya |  | UNIQUE |
| imei2 | varchar(20) | ya |  | UNIQUE |
| serial_number | varchar(50) | ya |  | UNIQUE |
| status | enum('in_stock','in_transit','reserved','sold','returned','in_service','defective','written_off') |  | in_stock |  |
| condition_grade | enum('new','A','B','C') |  | new |  |
| unit_cost | decimal(15,2) |  | 0.00 |  |
| sell_price | decimal(15,2) | ya |  |  |
| source_type | enum('purchase','trade_in','adjustment','return') |  |  |  |
| source_id | char(36) | ya |  |  |
| sold_sale_line_id | char(36) | ya |  |  |
| warranty_until | date | ya |  |  |
| notes | text | ya |  |  |
| created_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |
| updated_at | datetime(3) |  | CURRENT_TIMESTAMP(3) | index |

Relasi: `location_id` → `locations.id`, `variant_id` → `product_variants.id`

### `stock_movements`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| location_id | int |  |  | index |
| variant_id | int |  |  | index |
| unit_id | char(36) | ya |  | index |
| qty_change | int |  |  |  |
| unit_cost | decimal(15,2) |  | 0.00 |  |
| reason | enum('purchase','purchase_return','sale','sale_return','transfer_out','transfer_in','adjustment','opname','trade_in','service_part','write_off') |  |  |  |
| ref_type | varchar(30) | ya |  | index |
| ref_id | varchar(36) | ya |  |  |
| user_id | int | ya |  | index |
| device_id | char(36) | ya |  |  |
| note | text | ya |  |  |
| created_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

Relasi: `location_id` → `locations.id`, `unit_id` → `product_units.id`, `user_id` → `users.id`, `variant_id` → `product_variants.id`

### `stock_movements_legacy`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| product_id | int |  |  | index |
| branch_id | int |  |  | index |
| type | enum('in','out') |  |  |  |
| qty | int |  |  |  |
| note | text | ya |  |  |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime | ya | CURRENT_TIMESTAMP |  |

### `stock_on_hand` (view)

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| location_id | int | ya |  |  |
| variant_id | int | ya |  |  |
| qty | bigint | ya |  |  |

### `suppliers`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| code | varchar(20) |  |  | UNIQUE |
| name | varchar(150) |  |  |  |
| phone | varchar(30) | ya |  |  |
| email | varchar(100) | ya |  |  |
| address | text | ya |  |  |
| notes | text | ya |  |  |
| is_active | tinyint(1) |  | 1 |  |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime(3) | ya | CURRENT_TIMESTAMP(3) |  |
| deleted_at | datetime(3) | ya |  |  |

### `goods_receipts`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| number | varchar(30) |  |  | UNIQUE |
| supplier_id | int |  |  | index |
| location_id | int |  |  | index |
| invoice_no | varchar(50) | ya |  |  |
| invoice_date | date | ya |  |  |
| due_date | date | ya |  |  |
| status | enum('draft','posted') |  | draft |  |
| subtotal | decimal(15,2) |  | 0.00 |  |
| tax_total | decimal(15,2) |  | 0.00 |  |
| grand_total | decimal(15,2) |  | 0.00 |  |
| paid_total | decimal(15,2) |  | 0.00 |  |
| note | text | ya |  |  |
| created_by | int | ya |  | index |
| posted_by | int | ya |  | index |
| posted_at | datetime(3) | ya |  |  |
| created_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |
| updated_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

Relasi: `created_by` → `users.id`, `location_id` → `locations.id`, `posted_by` → `users.id`, `supplier_id` → `suppliers.id`

### `goods_receipt_items`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| receipt_id | char(36) |  |  | index |
| variant_id | int |  |  | index |
| qty | int |  |  |  |
| unit_cost | decimal(15,2) |  |  |  |
| tax_rate | decimal(5,2) |  | 0.00 |  |
| tax_amount | decimal(15,2) |  | 0.00 |  |
| line_total | decimal(15,2) |  |  |  |
| sort_order | int |  | 0 |  |

Relasi: `receipt_id` → `goods_receipts.id` (cascade), `variant_id` → `product_variants.id`

### `goods_receipt_units`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| receipt_item_id | char(36) |  |  | index |
| imei1 | varchar(20) | ya |  |  |
| imei2 | varchar(20) | ya |  |  |
| serial_number | varchar(50) | ya |  |  |
| condition_grade | enum('new','A','B','C') |  | new |  |
| unit_id | char(36) | ya |  | index |

Relasi: `receipt_item_id` → `goods_receipt_items.id` (cascade), `unit_id` → `product_units.id`

### `supplier_payments`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| supplier_id | int |  |  | index |
| receipt_id | char(36) | ya |  | index |
| amount | decimal(15,2) |  |  |  |
| method | enum('cash','transfer','giro','other') |  |  |  |
| reference | varchar(100) | ya |  |  |
| paid_at | date |  |  |  |
| note | text | ya |  |  |
| created_by | int | ya |  | index |
| created_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

Relasi: `created_by` → `users.id`, `receipt_id` → `goods_receipts.id`, `supplier_id` → `suppliers.id`

### `stock_transfers`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| number | varchar(30) |  |  | UNIQUE |
| from_location_id | int |  |  | index |
| to_location_id | int |  |  | index |
| status | enum('draft','sent','received','partially_received','cancelled') |  | draft |  |
| note | text | ya |  |  |
| created_by | int | ya |  |  |
| sent_by | int | ya |  |  |
| sent_at | datetime(3) | ya |  |  |
| received_by | int | ya |  |  |
| received_at | datetime(3) | ya |  |  |
| receive_note | text | ya |  |  |
| resolved_by | int | ya |  |  |
| resolved_at | datetime(3) | ya |  |  |
| created_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |
| updated_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

Relasi: `from_location_id` → `locations.id`, `to_location_id` → `locations.id`

### `stock_transfer_items`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| transfer_id | char(36) |  |  | index |
| variant_id | int |  |  | index |
| qty_sent | int |  |  |  |
| qty_received | int | ya |  |  |
| qty_resolved | int |  | 0 |  |
| unit_cost | decimal(15,2) |  | 0.00 |  |
| note | text | ya |  |  |
| sort_order | int |  | 0 |  |

Relasi: `transfer_id` → `stock_transfers.id` (cascade), `variant_id` → `product_variants.id`

### `stock_transfer_units`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| transfer_item_id | char(36) |  |  | PK |
| unit_id | char(36) |  |  | PK |
| outcome | enum('received','returned','written_off') | ya |  |  |

Relasi: `transfer_item_id` → `stock_transfer_items.id` (cascade), `unit_id` → `product_units.id`

### `stock_opnames`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| number | varchar(30) |  |  | UNIQUE |
| location_id | int |  |  | index |
| status | enum('counting','approved','cancelled') |  | counting |  |
| category_id | int | ya |  | index |
| note | text | ya |  |  |
| created_by | int | ya |  |  |
| approved_by | int | ya |  |  |
| approved_at | datetime(3) | ya |  |  |
| created_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |
| updated_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

Relasi: `category_id` → `categories.id`, `location_id` → `locations.id`

### `stock_opname_items`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| opname_id | char(36) |  |  | index |
| variant_id | int |  |  | index |
| system_qty | int |  |  |  |
| counted_qty | int | ya |  |  |
| note | text | ya |  |  |

Relasi: `opname_id` → `stock_opnames.id` (cascade), `variant_id` → `product_variants.id`

### `stock_opname_units`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| opname_id | char(36) |  |  | PK |
| unit_id | char(36) |  |  | PK |
| found | tinyint(1) |  | 0 |  |

Relasi: `opname_id` → `stock_opnames.id` (cascade), `unit_id` → `product_units.id`

### `stock_opname_extras`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| opname_id | char(36) |  |  | index |
| identifier | varchar(50) |  |  |  |
| unit_id | char(36) | ya |  | index |
| created_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

Relasi: `opname_id` → `stock_opnames.id` (cascade), `unit_id` → `product_units.id`

### `payment_methods`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| name | varchar(50) |  |  |  |
| type | enum('cash','qris','ewallet','card','transfer') |  |  |  |
| account_id | int |  |  | index |
| requires_reference | tinyint(1) |  | 0 |  |
| location_id | int | ya |  | index |
| sort_order | int |  | 0 |  |
| is_active | tinyint(1) |  | 1 |  |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime(3) | ya | CURRENT_TIMESTAMP(3) |  |

Relasi: `account_id` → `accounts.id`, `location_id` → `locations.id` (cascade)

### `customers`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| code | varchar(30) | ya |  | UNIQUE |
| name | varchar(150) |  |  | index |
| phone | varchar(30) | ya |  | UNIQUE |
| email | varchar(100) | ya |  |  |
| address | text | ya |  |  |
| id_number | varchar(30) | ya |  |  |
| notes | text | ya |  |  |
| created_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |
| updated_at | datetime(3) |  | CURRENT_TIMESTAMP(3) | index |
| deleted_at | datetime(3) | ya |  |  |

### `cash_sessions`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| location_id | int |  |  | index |
| device_id | char(36) | ya |  |  |
| status | enum('open','closed') |  | open |  |
| opened_by | int |  |  | index |
| opened_at | datetime(3) |  |  |  |
| opening_cash | decimal(15,2) |  | 0.00 |  |
| closed_by | int | ya |  | index |
| closed_at | datetime(3) | ya |  |  |
| expected_cash | decimal(15,2) | ya |  |  |
| counted_cash | decimal(15,2) | ya |  |  |
| difference | decimal(15,2) | ya |  |  |
| note | text | ya |  |  |
| created_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |
| updated_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

Relasi: `closed_by` → `users.id`, `location_id` → `locations.id`, `opened_by` → `users.id`

### `sales`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| number | varchar(40) |  |  | UNIQUE |
| location_id | int |  |  | index |
| device_id | char(36) | ya |  |  |
| cash_session_id | char(36) | ya |  | index |
| cashier_id | int |  |  | index |
| customer_id | char(36) | ya |  | index |
| voucher_id | int | ya |  | index |
| subtotal | decimal(15,2) |  |  |  |
| discount_total | decimal(15,2) |  | 0.00 |  |
| tax_total | decimal(15,2) |  | 0.00 |  |
| grand_total | decimal(15,2) |  |  |  |
| paid_total | decimal(15,2) |  |  |  |
| change_total | decimal(15,2) |  | 0.00 |  |
| refunded_total | decimal(15,2) |  | 0.00 |  |
| status | enum('completed','voided','partially_returned','returned') |  | completed |  |
| note | text | ya |  |  |
| void_reason | text | ya |  |  |
| voided_by | int | ya |  |  |
| voided_at | datetime(3) | ya |  |  |
| occurred_at | datetime(3) |  |  |  |
| received_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |
| sync_flags | json | ya |  |  |
| updated_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

Relasi: `cash_session_id` → `cash_sessions.id`, `cashier_id` → `users.id`, `customer_id` → `customers.id`, `location_id` → `locations.id`, `voucher_id` → `vouchers.id`

### `sale_lines`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| sale_id | char(36) |  |  | index |
| line_type | enum('goods','service','digital','fee') |  | goods |  |
| variant_id | int | ya |  | index |
| unit_id | char(36) | ya |  | index |
| description | varchar(200) |  |  |  |
| qty | int |  |  |  |
| unit_price | decimal(15,2) |  |  |  |
| discount | decimal(15,2) |  | 0.00 |  |
| tax_rate | decimal(5,2) |  | 0.00 |  |
| tax_amount | decimal(15,2) |  | 0.00 |  |
| line_total | decimal(15,2) |  |  |  |
| unit_cost | decimal(15,2) |  | 0.00 |  |
| returned_qty | int |  | 0 |  |
| warranty_until | date | ya |  |  |
| sort_order | int |  | 0 |  |

Relasi: `sale_id` → `sales.id` (cascade), `unit_id` → `product_units.id`, `variant_id` → `product_variants.id`

### `sale_payments`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| sale_id | char(36) |  |  | index |
| payment_method_id | int |  |  | index |
| amount | decimal(15,2) |  |  |  |
| reference | varchar(100) | ya |  |  |

Relasi: `payment_method_id` → `payment_methods.id`, `sale_id` → `sales.id` (cascade)

### `sale_returns`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| number | varchar(30) |  |  | UNIQUE |
| sale_id | char(36) |  |  | index |
| location_id | int |  |  | index |
| cash_session_id | char(36) | ya |  | index |
| refund_method_id | int |  |  | index |
| refund_total | decimal(15,2) |  |  |  |
| tax_total | decimal(15,2) |  | 0.00 |  |
| reason | text |  |  |  |
| created_by | int | ya |  | index |
| created_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

Relasi: `cash_session_id` → `cash_sessions.id`, `created_by` → `users.id`, `location_id` → `locations.id`, `refund_method_id` → `payment_methods.id`, `sale_id` → `sales.id`

### `sale_return_lines`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| return_id | char(36) |  |  | index |
| sale_line_id | char(36) |  |  | index |
| qty | int |  |  |  |
| amount | decimal(15,2) |  |  |  |
| tax_amount | decimal(15,2) |  | 0.00 |  |
| unit_cost | decimal(15,2) |  | 0.00 |  |
| restock | tinyint(1) |  | 1 |  |

Relasi: `return_id` → `sale_returns.id` (cascade), `sale_line_id` → `sale_lines.id`

### `vouchers`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| code | varchar(50) |  |  | UNIQUE |
| description | text | ya |  |  |
| target_type | enum('categories','product') | ya |  |  |
| target_id | bigint | ya |  | index |
| discount_type | enum('percent','fixed') |  |  |  |
| discount_value | decimal(12,2) |  |  |  |
| valid_from | date | ya |  |  |
| valid_to | date | ya |  |  |
| is_active | tinyint(1) | ya | 1 |  |
| created_at | timestamp |  | CURRENT_TIMESTAMP |  |
| updated_at | timestamp |  | CURRENT_TIMESTAMP |  |

### `accounts`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| code | varchar(20) |  |  | UNIQUE |
| name | varchar(100) |  |  |  |
| type | enum('asset','liability','equity','income','expense') |  |  |  |
| parent_id | int | ya |  | index |
| is_postable | tinyint(1) |  | 1 |  |
| is_system | tinyint(1) |  | 0 |  |
| is_active | tinyint(1) |  | 1 |  |
| created_at | datetime | ya | CURRENT_TIMESTAMP |  |
| updated_at | datetime(3) | ya | CURRENT_TIMESTAMP(3) |  |

Relasi: `parent_id` → `accounts.id`

### `account_mappings`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK, auto |
| key | varchar(50) |  |  | index |
| location_id | int | ya |  | index |
| account_id | int |  |  | index |

Relasi: `account_id` → `accounts.id`, `location_id` → `locations.id` (cascade)

### `accounting_periods`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| year | smallint |  |  | PK |
| month | tinyint |  |  | PK |
| status | enum('open','closed') |  | open |  |
| closed_by | int | ya |  | index |
| closed_at | datetime(3) | ya |  |  |

Relasi: `closed_by` → `users.id`

### `journal_entries`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| number | varchar(30) |  |  | UNIQUE |
| entry_date | date |  |  | index |
| location_id | int | ya |  | index |
| source_type | enum('sale','sale_void','sale_return','goods_receipt','supplier_payment','stock_adjustment','opname','transfer','cash_session','expense','manual') |  |  | index |
| source_id | varchar(36) | ya |  |  |
| memo | varchar(255) | ya |  |  |
| status | enum('posted','void') |  | posted |  |
| reverses_entry_id | char(36) | ya |  | index |
| created_by | int | ya |  | index |
| created_at | datetime(3) |  | CURRENT_TIMESTAMP(3) |  |

Relasi: `created_by` → `users.id`, `location_id` → `locations.id`, `reverses_entry_id` → `journal_entries.id`

### `journal_lines`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | char(36) |  |  | PK |
| entry_id | char(36) |  |  | index |
| account_id | int |  |  | index |
| location_id | int | ya |  | index |
| debit | decimal(15,2) |  | 0.00 |  |
| credit | decimal(15,2) |  | 0.00 |  |
| memo | varchar(255) | ya |  |  |

Relasi: `account_id` → `accounts.id`, `entry_id` → `journal_entries.id` (cascade), `location_id` → `locations.id`

### `absensi`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int |  |  | PK |
| absensi_image | varchar(255) |  |  |  |
| kehadiran | enum('Hadir','Izin','Sakit','Tidak Masuk','Tanpa Keterangan') |  |  |  |
| users_id | int |  |  | index |
| branches_id | int |  |  | index |
| created_at | timestamp |  | CURRENT_TIMESTAMP |  |
| updated_at | timestamp |  | CURRENT_TIMESTAMP |  |

### `knex_migrations`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| id | int unsigned |  |  | PK, auto |
| name | varchar(255) | ya |  |  |
| batch | int | ya |  |  |
| migration_time | timestamp | ya |  |  |

### `knex_migrations_lock`

| Kolom | Tipe | Null | Default | Kunci |
| --- | --- | --- | --- | --- |
| index | int unsigned |  |  | PK, auto |
| is_locked | int | ya |  |  |
