# GG Store Cashier

Sistem Point of Sale (POS) dengan backend Express.js dan aplikasi mobile Flutter.

---

## Prasyarat

- Node.js >= 18.0.0
- npm >= 9.0.0
- Flutter 3.38.5 (via FVM)
- Android Studio dengan NDK 27.0.12077973
- Database MySQL

---

## Cara Setup

### 1. Install dependensi Node

```bash
npm install
```

### 2. Install Flutter via FVM

```bash
cd app
dart pub global activate fvm
fvm install 3.38.5
fvm flutter pub get
```

### 3. Konfigurasi environment

Buat file `.env` di root proyek:

```env
# Database
DB_HOST=localhost
DB_PORT=3306
DB_USER=your_user
DB_PASS=your_password
DB_NAME=gg_store

# API
PORT=3000
JWT_SECRET=your_secret_key

# Ngrok (untuk development)
NGROK_API_URL=http://localhost:3000
NGROK_API_TIMEOUT=30000
```

### 4. Siapkan database (migrasi)

Buat database kosong sesuai `DB_NAME`, lalu jalankan:

```bash
npm run migrate
```

Skema database dikelola dengan migrasi [Knex](https://knexjs.org) di `API/migrations/`. Migrasi pertama (`baseline`) membuat skema awal jika tabel belum ada; pada database lama yang sudah berisi tabel, migrasi ini hanya dicatat sebagai sudah dijalankan tanpa mengubah data.

| Perintah                          | Fungsi                                              |
| --------------------------------- | --------------------------------------------------- |
| `npm run migrate`                 | Menjalankan semua migrasi yang belum dijalankan.    |
| `npm run migrate:status`          | Menampilkan migrasi yang sudah dan belum dijalankan. |
| `npm run migrate:rollback`        | Membatalkan batch migrasi terakhir.                 |
| `npm run migrate:make -- <nama>`  | Membuat file migrasi baru.                          |
| `npm run seed`                    | Menjalankan seed di `API/seeds/`.                   |

Setiap perubahan skema harus dibuat sebagai file migrasi baru — jangan ubah tabel langsung di database atau mengedit migrasi yang sudah dijalankan.

Setelah migrasi akuntansi (penjualan & jurnal) pertama kali dijalankan, buat jurnal untuk transaksi, penerimaan barang, dan pembayaran supplier yang sudah ada:

```bash
npm run accounting:backfill
```

Perintah ini aman dijalankan berulang kali; dokumen yang sudah punya jurnal dilewati.

Migrasi langkah 6 (`cleanup_legacy_access`) menghapus `users.role`, `users.branch_id` dan view `branches`. Hak akses
sepenuhnya berasal dari penugasan role per lokasi (`user_locations`), yang sudah dibuat dari data lama di langkah 2.
Sebelum menjalankannya, pastikan setiap pengguna punya penugasan (cek di menu Manajemen Pengguna); pengguna tanpa penugasan
masih bisa login tetapi tidak bisa melakukan apa pun sampai diberi role.

Setelah migrasi, perbarui dokumentasi skema:

```bash
npm run db:docs
```

Perintah ini menulis ulang `Database.md` dari skema database yang sedang dipakai.

### 5. Jalankan proyek

**Opsi A: Jalankan terpisah**

- API: `npm run dev` (dengan hot reload + ngrok)
- Flutter: Gunakan VS Code Run & Debug → "Flutter (Mobile App via FVM)"

**Opsi B: Jalankan bersamaan**

- Gunakan VS Code Run & Debug → "Full Stack (Flutter + API)"

### 6. Back-office web (`web/`)

Aplikasi web terpisah (React + Vite + TypeScript) untuk owner, manajer, gudang, dan akuntan: pengguna & role,
lokasi, katalog, stok & IMEI, penerimaan barang, transfer, stok opname, penjualan (batal/retur), shift, pelanggan,
voucher, analitik, dan akuntansi (jurnal, neraca saldo, laba rugi, bagan akun, periode, pemetaan akun). Laporan
bisa diekspor ke CSV. Aplikasi Flutter tidak dibangun untuk web.

```bash
cd web
npm install
npm run dev
```

Buka http://localhost:5173. Saat development, Vite meneruskan `/api` dan `/uploads` ke API (default
`http://localhost:3000`; ubah dengan `API_URL=...` di `web/.env.local`), jadi browser melihat satu origin dan
cookie sesi API (httpOnly, SameSite=Lax) langsung bekerja. Token tidak pernah disimpan di JavaScript.

Produksi: `npm run build` menghasilkan file statis di `web/dist/`. Sajikan dari domain yang sama dengan API lewat
reverse proxy (mis. nginx: `/` → `web/dist` dengan fallback ke `index.html`, `/api` dan `/uploads` → server
Node). Jika web harus di domain lain, set `VITE_API_URL` saat build dan tambahkan origin web ke `CORS_ORIGIN`;
cookie lintas situs juga perlu `SameSite=None; Secure`, jadi satu domain lebih disarankan.

Menu dan halaman mengikuti izin pengguna (sama dengan aplikasi kasir); API tetap memeriksa setiap permintaan.

---

## Struktur Proyek

### Root

| Nama File/Folder | Tipe     | Deskripsi                                                              |
| ---------------- | -------- | ---------------------------------------------------------------------- |
| `README.md`      | Markdown | File ini — dokumentasi dan penjelasan proyek.                          |
| `.env`           | Env      | Konfigurasi environment (database, JWT, ngrok URL).                    |
| `API/`           | Folder   | Folder utama backend Express.js.                                       |
| `app/`           | Folder   | Folder utama aplikasi Flutter.                                         |
| `web/`           | Folder   | Back-office web (React + Vite), memakai API yang sama.                  |
| `.vscode/`       | Folder   | Konfigurasi debug VS Code untuk menjalankan Flutter dan API sekaligus. |

### API/

| Nama File/Folder                 | Tipe       | Deskripsi                                                             |
| -------------------------------- | ---------- | --------------------------------------------------------------------- |
| `API/src/server.js`              | JavaScript | Entry point server — inisialisasi Express, middleware, dan Socket.IO. |
| `API/src/db.js`                  | JavaScript | Koneksi ke database MySQL menggunakan `mysql2`.                       |
| `API/src/routes/auth.js`         | JavaScript | Route autentikasi: login, logout, dan cek user aktif.                 |
| `API/src/routes/users.js`        | JavaScript | Route manajemen pengguna beserta penugasan role per lokasi.           |
| `API/src/routes/categories.js`   | JavaScript | Route manajemen kategori produk.                                      |
| `API/src/routes/vouchers.js`     | JavaScript | Route manajemen voucher diskon.                                       |
| `API/src/routes/dashboard.js`    | JavaScript | Route statistik dashboard (pendapatan, stok, transaksi terbaru).      |
| `API/src/routes/analytics.js`    | JavaScript | Route analitik semua lokasi (izin `reports.view_all`).                |
| `API/src/routes/catalog.js`      | JavaScript | Route katalog: produk, varian, merek, tarif pajak, gambar produk.     |
| `API/src/routes/stock.js`        | JavaScript | Route stok per lokasi: penyesuaian, harga lokasi, unit IMEI, riwayat. |
| `API/src/services/stock.js`      | JavaScript | Satu-satunya kode yang mengubah stok; selalu mencatat `stock_movements`. |
| `API/src/routes/sales.js`        | JavaScript | Penjualan (harga termasuk PPN, IMEI, split payment), batal, retur, metode bayar. |
| `API/src/routes/cash_sessions.js` | JavaScript | Shift kasir: buka, ringkasan, tutup dengan hitung kas.               |
| `API/src/routes/customers.js`    | JavaScript | Pelanggan (dicari lewat nomor HP) beserta riwayat dan garansi IMEI.   |
| `API/src/routes/accounting.js`   | JavaScript | Bagan akun, jurnal manual, neraca saldo, laba rugi, tutup periode, pemetaan akun. |
| `API/src/services/journal.js`    | JavaScript | Mesin jurnal: harus seimbang, tidak bisa diedit (dibatalkan via jurnal pembalik). |
| `API/src/services/posting.js`    | JavaScript | Aturan jurnal otomatis untuk penjualan, retur, pembelian, stok, dan shift. |
| `API/scripts/backfill-journals.js` | JavaScript | `npm run accounting:backfill` — membuat jurnal untuk dokumen lama.   |
| `API/scripts/schema-doc.js`      | JavaScript | `npm run db:docs` — menulis ulang `Database.md` dari skema database.  |
| `API/src/routes/purchasing.js`   | JavaScript | Supplier, penerimaan barang (draf → posting ke stok), pembayaran supplier. |
| `API/src/routes/transfers.js`    | JavaScript | Transfer stok antar lokasi: draf → kirim → terima / selesaikan selisih. |
| `API/src/routes/opnames.js`      | JavaScript | Stok opname: snapshot, hitung jumlah, scan IMEI, setujui penyesuaian. |
| `API/src/services/documents.js`  | JavaScript | Penomoran dokumen per lokasi per hari (mis. `GR-WH-261031-0001`).     |
| `API/src/routes/locations.js`    | JavaScript | Route lokasi (cabang dan gudang): daftar, tambah, ubah, nonaktifkan.  |
| `API/src/routes/access.js`       | JavaScript | Route role, daftar izin, dan penugasan role pengguna per lokasi.      |
| `API/src/middleware/auth.js`     | JavaScript | Middleware JWT dan `requirePermission` (izin per lokasi).             |
| `API/src/auth/permissions.js`    | JavaScript | Daftar semua kunci izin (permission) yang diperiksa API.              |
| `API/src/services/access.js`     | JavaScript | Memuat izin pengguna per lokasi dan memvalidasi penugasan role.       |
| `API/src/services/audit.js`      | JavaScript | Pencatatan audit log perubahan data penting.                          |
| `API/src/utils/upload.js`        | JavaScript | Konfigurasi Multer untuk upload gambar produk dan kategori.           |
| `API/src/public/api-docs.js`     | JavaScript | Script frontend untuk halaman dokumentasi API berbasis web.           |
| `API/src/public/docs-login.js`   | JavaScript | Script frontend untuk halaman login dokumentasi.                      |
| `API/src/views/api-docs.html`    | HTML       | Template halaman dokumentasi API.                                     |
| `API/src/views/docs-login.html`  | HTML       | Template halaman login untuk akses dokumentasi.                       |
| `API/uploads/products/`          | Folder     | Penyimpanan gambar produk yang diupload.                              |
| `API/uploads/categories/`        | Folder     | Penyimpanan gambar kategori yang diupload.                            |
| `API/uploads/absensi/`           | Folder     | Penyimpanan foto absensi karyawan.                                    |
| `API/uploads/temp/`              | Folder     | Folder sementara untuk file yang sedang diproses.                     |
| `API/uploads/thumbnails/`        | Folder     | Thumbnail gambar yang sudah dikompresi.                               |
| `API/scripts/sync-env.js`        | JavaScript | Script untuk menyinkronkan URL ngrok ke file `.env` Flutter.          |
| `API/knexfile.js`                | JavaScript | Konfigurasi Knex untuk migrasi (membaca kredensial dari `.env`).      |
| `API/migrations/`                | Folder     | File migrasi skema database, dijalankan berurutan oleh Knex.          |
| `API/seeds/`                     | Folder     | Data awal (seed) untuk database.                                      |

### app/

| Nama File/Folder    | Tipe   | Deskripsi                                                           |
| ------------------- | ------ | ------------------------------------------------------------------- |
| `app/lib/main.dart` | Dart   | Entry point aplikasi Flutter — inisialisasi Hive, router, dan tema. |
| `app/lib/core/`     | Folder | Komponen inti: config, model, provider, router, service, tema.      |
| `app/lib/features/` | Folder | Fitur-fitur aplikasi: auth, cashier, inventory, settings, dll.      |
| `app/lib/shared/`   | Folder | Widget dan utilitas yang digunakan bersama antar fitur.             |
| `app/android/`      | Folder | Konfigurasi native Android (NDK, permissions, build config).        |

### web/

| Nama File/Folder           | Tipe   | Deskripsi                                                               |
| -------------------------- | ------ | ----------------------------------------------------------------------- |
| `web/src/api/`             | Folder | Klien API (`fetch` dengan cookie sesi) dan tipe respons API.            |
| `web/src/auth/`            | Folder | Sesi login dan `Access` (izin per lokasi, sama seperti di API).          |
| `web/src/components/`      | Folder | Komponen UI bersama dan layout (sidebar sesuai izin, penjaga halaman).  |
| `web/src/lib/`             | Folder | Format Rupiah/tanggal, pemilih lokasi, pemilih produk, ekspor CSV.      |
| `web/src/pages/`           | Folder | Halaman per modul: admin, catalog, stock, purchasing, transfers, opnames, sales, accounting. |
| `web/vite.config.ts`       | TS     | Konfigurasi Vite dan proxy `/api` ke API saat development.              |

---


## Peran Pengguna

Hak akses diberikan per lokasi: satu pengguna bisa menjadi manajer di BR01 dan kasir di BR02. Setiap role adalah
kumpulan izin (`API/src/auth/permissions.js`); API memeriksa izin di lokasi yang diminta, aplikasi hanya
menyembunyikan menu yang tidak bisa dipakai.

| Role             | Deskripsi                                                                                   |
| ---------------- | ------------------------------------------------------------------------------------------- |
| `owner`          | Semua izin di semua lokasi.                                                                 |
| `branch_manager` | Penjualan, batal/retur, shift, stok & opname, transfer, pelanggan, pengguna, voucher, data cabang, laporan cabang. |
| `cashier`        | Penjualan, shift kasir, lihat katalog & stok, pelanggan.                                    |
| `warehouse`      | Katalog, stok, IMEI, transfer, opname, penerimaan barang, supplier, impor/ekspor.           |
| `accountant`     | Jurnal, tutup periode, laporan semua lokasi, pembelian & supplier, impor/ekspor.            |

Role kustom bisa dibuat lewat `/api/access/roles` (izin `roles.manage`). Pengguna hanya bisa memberikan role yang
izinnya ia miliki sendiri di lokasi tersebut.

---

## Dokumentasi API

Dokumentasi lengkap (semua endpoint, izin yang dibutuhkan, body, contoh respons) tersedia di **`/api/docs`**
saat server berjalan — login dengan akun owner. Ringkasan:

| Prefix                     | Isi                                                                                       |
| -------------------------- | ----------------------------------------------------------------------------------------- |
| `/api/auth`                | Login (mengembalikan token dan `access`: role & izin per lokasi), logout, `me`.           |
| `/api/users`               | Pengguna + penugasan `assignments: [{ location_id, role_id }]` (izin `users.manage`).     |
| `/api/access`              | Daftar izin, role (buat/ubah/hapus), penugasan pengguna.                                  |
| `/api/locations`           | Cabang & gudang.                                                                          |
| `/api/catalog`, `/api/categories` | Produk, varian, merek, tarif pajak, kategori.                                     |
| `/api/stock`               | Stok per lokasi, penyesuaian, harga lokasi, unit IMEI, riwayat stok.                      |
| `/api/purchasing`          | Supplier, penerimaan barang, pembayaran supplier.                                         |
| `/api/transfers`           | Transfer stok antar lokasi.                                                               |
| `/api/opnames`             | Stok opname.                                                                              |
| `/api/sales`               | Penjualan (idempoten per UUID klien), `/quote`, batal, retur, metode pembayaran.          |
| `/api/customers`, `/api/cash-sessions` | Pelanggan dan shift kasir.                                                  |
| `/api/vouchers`            | Voucher (`vouchers.manage`); `/validate/:code` untuk kasir.                               |
| `/api/accounting`          | Akun, jurnal, neraca saldo, laba rugi, periode, pemetaan akun.                            |
| `/api/dashboard`, `/api/analytics` | Ringkasan untuk lokasi pengguna; analitik semua lokasi (`reports.view_all`).    |

Endpoint lama `/api/products`, `/api/branches`, `/api/transactions`, `/api/admins` dan `/api/super` sudah dihapus;
gunakan `/api/catalog`, `/api/locations` dan `/api/sales`.

### ⚡ Socket.IO Events

Koneksi wajib membawa token API (`auth: { token }` atau header `Authorization: Bearer <token>`). Bergabung ke room lokasi
untuk menerima update real-time:

```dart
socket.emit('join-branch', locationId); // room satu lokasi (harus punya akses penjualan/laporan di sana)
socket.emit('join-branch', 0);          // semua lokasi — hanya untuk akses yang mencakup semua lokasi
```

| Event           | Payload                                        | Dipicu saat                          |
| --------------- | ---------------------------------------------- | ------------------------------------ |
| `sale-created`  | `{ id, number, grand_total, location_id? }`    | Penjualan baru tersimpan             |
| `stock-changed` | `{ location_id, variant_ids }`                 | Stok berubah karena penjualan        |
| `server-info`   | status server                                  | Setiap 10 detik (halaman docs)       |

---

### ⚙️ Environment Variables

| Variabel          | Wajib | Deskripsi                                               |
| ----------------- | ----- | ------------------------------------------------------- |
| `PORT`            | ❌    | Port server (default: 3000)                             |
| `NODE_ENV`        | ❌    | `development` atau `production`                         |
| `DB_HOST`         | ✅    | Host MySQL                                              |
| `DB_USER`         | ✅    | Username MySQL                                          |
| `DB_PASS`         | ✅    | Password MySQL                                          |
| `DB_NAME`         | ✅    | Nama database MySQL                                     |
| `JWT_SECRET`      | ✅    | Secret key untuk signing JWT                            |
| `CORS_ORIGIN`     | ❌    | Origin yang diizinkan untuk CORS (pisahkan dengan koma) |
| `NGROK_AUTHTOKEN` | ❌    | Auth token ngrok (mengaktifkan tunnel)                  |
| `API_TIMEOUT`     | ❌    | Timeout yang ditulis ke `app/.env` (default: 30000)     |
| `RATE_LIMIT_WINDOW_MS` | ❌ | Jendela rate limit dalam ms (default: 60000)        |
| `RATE_LIMIT_USER_MAX`  | ❌ | Maks. permintaan per pengguna per jendela (default: 300) |
| `RATE_LIMIT_ANON_MAX`  | ❌ | Maks. permintaan tanpa token per IP per jendela (default: 60) |

Rate limit dihitung per pengguna yang login (perangkat di satu toko biasanya memakai satu IP publik); permintaan tanpa
token dihitung per IP. `/api/health` dan `/api/test` (cek koneksi aplikasi) tidak dibatasi. Percobaan login punya
penguncian sendiri (5 kali gagal → 15 menit).
