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

### 5. Jalankan proyek

**Opsi A: Jalankan terpisah**

- API: `npm run dev` (dengan hot reload + ngrok)
- Flutter: Gunakan VS Code Run & Debug → "Flutter (Mobile App via FVM)"

**Opsi B: Jalankan bersamaan**

- Gunakan VS Code Run & Debug → "Full Stack (Flutter + API)"

---

## Struktur Proyek

### Root

| Nama File/Folder | Tipe     | Deskripsi                                                              |
| ---------------- | -------- | ---------------------------------------------------------------------- |
| `README.md`      | Markdown | File ini — dokumentasi dan penjelasan proyek.                          |
| `.env`           | Env      | Konfigurasi environment (database, JWT, ngrok URL).                    |
| `API/`           | Folder   | Folder utama backend Express.js.                                       |
| `app/`           | Folder   | Folder utama aplikasi Flutter.                                         |
| `.vscode/`       | Folder   | Konfigurasi debug VS Code untuk menjalankan Flutter dan API sekaligus. |

### API/

| Nama File/Folder                 | Tipe       | Deskripsi                                                             |
| -------------------------------- | ---------- | --------------------------------------------------------------------- |
| `API/src/server.js`              | JavaScript | Entry point server — inisialisasi Express, middleware, dan Socket.IO. |
| `API/src/db.js`                  | JavaScript | Koneksi ke database MySQL menggunakan `mysql2`.                       |
| `API/src/routes/auth.js`         | JavaScript | Route autentikasi: login, logout, dan cek user aktif.                 |
| `API/src/routes/users.js`        | JavaScript | Route manajemen pengguna (CRUD) dengan filter role dan cabang.        |
| `API/src/routes/admins.js`       | JavaScript | Route khusus admin — operasi yang hanya bisa dilakukan admin.         |
| `API/src/routes/super.js`        | JavaScript | Route khusus superadmin — akses lintas cabang.                        |
| `API/src/routes/products.js`     | JavaScript | Route manajemen produk termasuk upload gambar.                        |
| `API/src/routes/categories.js`   | JavaScript | Route manajemen kategori produk.                                      |
| `API/src/routes/branches.js`     | JavaScript | Route manajemen cabang toko.                                          |
| `API/src/routes/transactions.js` | JavaScript | Route transaksi kasir — validasi stok, potong stok, real-time event.  |
| `API/src/routes/vouchers.js`     | JavaScript | Route manajemen voucher diskon.                                       |
| `API/src/routes/dashboard.js`    | JavaScript | Route statistik dashboard (pendapatan, stok, transaksi terbaru).      |
| `API/src/routes/analytics.js`    | JavaScript | Route analitik lanjutan khusus superadmin.                            |
| `API/src/routes/catalog.js`      | JavaScript | Route katalog: produk, varian, merek, tarif pajak, gambar produk.     |
| `API/src/routes/stock.js`        | JavaScript | Route stok per lokasi: penyesuaian, harga lokasi, unit IMEI, riwayat. |
| `API/src/services/stock.js`      | JavaScript | Satu-satunya kode yang mengubah stok; selalu mencatat `stock_movements`. |
| `API/src/services/legacy-products.js` | JavaScript | Lapisan kompatibilitas `/api/products` lama di atas tabel katalog. |
| `API/src/routes/locations.js`    | JavaScript | Route lokasi (cabang dan gudang): daftar, tambah, ubah, nonaktifkan.  |
| `API/src/routes/access.js`       | JavaScript | Route role, daftar izin, dan penugasan role pengguna per lokasi.      |
| `API/src/middleware/auth.js`     | JavaScript | Middleware JWT, `requireRole` (lama), dan `requirePermission`.        |
| `API/src/auth/permissions.js`    | JavaScript | Daftar semua kunci izin (permission) yang diperiksa API.              |
| `API/src/services/access.js`     | JavaScript | Memuat izin pengguna per lokasi; sinkronisasi dengan `users.role`.    |
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

---


## Peran Pengguna

| Role         | Deskripsi                                                   |
| ------------ | ----------------------------------------------------------- |
| `karyawan`   | Kasir — bisa membuat transaksi dan melihat produk           |
| `admin`      | Manajer cabang — mengelola pengguna dan produk di cabangnya |
| `superadmin` | Akses penuh ke semua cabang                                 |

---

## Dokumentasi API
---

### 🔐 Autentikasi

#### Login

- URL
  - `/api/auth/login`
- Method
  - `POST`
- Request Body
  - `username` as `string`
  - `password` as `string`
- Response

```json
{
  "token": "jwt_token",
  "user": {
    "id": 1,
    "name": "string",
    "username": "string",
    "role": "karyawan | admin | superadmin",
    "branchId": 1
  }
}
```

> Rate limited: 5 percobaan gagal → lockout 15 menit per kombinasi IP+username.

---

#### Logout

- URL
  - `/api/auth/logout`
- Method
  - `POST`
- Response

```json
{ "message": "Logout berhasil" }
```

---

#### Cek User Aktif

- URL
  - `/api/auth/me`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Response

```json
{
  "id": 1,
  "name": "string",
  "username": "string",
  "role": "string",
  "branchId": 1
}
```

---

### 👤 Pengguna

> `admin` hanya bisa mengelola pengguna di cabangnya sendiri.

#### Daftar Pengguna

- URL
  - `/api/users`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Query Params
  - `branch_id` — filter berdasarkan cabang (khusus superadmin)
  - `role` — filter: `karyawan`, `admin`, `superadmin`
  - `search` — cari berdasarkan nama atau username
  - `page` — nomor halaman (default: 1)
  - `limit` — jumlah per halaman (default: 10)
- Response

```json
{
  "users": [{ "id": 1, "name": "string", "username": "string", "role": "string", "branchId": 1 }],
  "total": 10,
  "page": 1
}
```

---

#### Buat Pengguna

- URL
  - `/api/users`
- Method
  - `POST`
- Headers
  - `Authorization`: `Bearer <token>`
- Request Body
  - `name` as `string`
  - `username` as `string`
  - `password` as `string` — min 8 karakter, harus ada huruf besar, kecil, dan angka
  - `role` as `string` — `karyawan | admin | superadmin`
  - `branch_id` as `number`
- Response

```json
{ "message": "Pengguna berhasil dibuat", "id": 5 }
```

---

#### Update Pengguna

- URL
  - `/api/users/:id`
- Method
  - `PUT`
- Headers
  - `Authorization`: `Bearer <token>`
- Request Body — field yang ingin diubah (semua opsional)
  - `name` as `string`
  - `password` as `string`
  - `role` as `string`
  - `branch_id` as `number`
- Response

```json
{ "message": "Pengguna berhasil diperbarui" }
```

---

#### Hapus Pengguna

- URL
  - `/api/users/:id`
- Method
  - `DELETE`
- Headers
  - `Authorization`: `Bearer <token>`
- Response

```json
{ "message": "Pengguna berhasil dihapus" }
```

---

### 📦 Produk

> Data otomatis difilter berdasarkan cabang sesuai role.

#### Daftar Produk

- URL
  - `/api/products`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Query Params
  - `branch_id` — filter berdasarkan cabang
  - `category_id` — filter berdasarkan kategori
  - `search` — cari berdasarkan nama atau barcode
- Response

```json
{
  "products": [
    {
      "id": 1,
      "name": "string",
      "barcode": "string",
      "sell_price": 15000,
      "stock": 10,
      "category_name": "string",
      "product_image": "filename.jpg",
      "branch_id": 1
    }
  ]
}
```

---

#### Buat Produk

- URL
  - `/api/products`
- Method
  - `POST`
- Headers
  - `Authorization`: `Bearer <token>`
  - `Content-Type`: `multipart/form-data`
- Request Body
  - `name` as `string` — wajib
  - `sell_price` as `number` — wajib
  - `branch_id` as `number` — wajib
  - `barcode` as `string` — opsional, auto-generate jika kosong
  - `category_id` as `number` — opsional
  - `stock` as `number` — opsional, default 0
  - `product_image` as `file` — opsional, jpg/png
- Response

```json
{ "message": "Produk berhasil dibuat", "id": 10 }
```

> Gambar diakses di: `GET /uploads/products/<nama_file>`

---

#### Update Produk

- URL
  - `/api/products/:id`
- Method
  - `PUT`
- Headers
  - `Authorization`: `Bearer <token>`
  - `Content-Type`: `multipart/form-data`
- Request Body — sama seperti buat produk, semua opsional
- Response

```json
{ "message": "Produk berhasil diperbarui" }
```

---

#### Hapus Produk

- URL
  - `/api/products/:id`
- Method
  - `DELETE`
- Headers
  - `Authorization`: `Bearer <token>`
- Role
  - `superadmin`
- Response

```json
{ "message": "Produk berhasil dihapus" }
```

---

### 🗂️ Kategori

#### Daftar Kategori

- URL
  - `/api/categories`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Response

```json
{
  "categories": [{ "id": 1, "name": "string", "description": "string", "category_image": "filename.jpg" }]
}
```

---

#### Buat Kategori

- URL
  - `/api/categories`
- Method
  - `POST`
- Headers
  - `Authorization`: `Bearer <token>`
  - `Content-Type`: `multipart/form-data`
- Request Body
  - `name` as `string` — wajib
  - `description` as `string` — opsional
  - `category_image` as `file` — opsional, jpg/png
- Response

```json
{ "message": "Kategori berhasil dibuat", "id": 3 }
```

> Gambar diakses di: `GET /uploads/categories/<nama_file>`

---

#### Hapus Kategori

- URL
  - `/api/categories/:id`
- Method
  - `DELETE`
- Headers
  - `Authorization`: `Bearer <token>`
- Role
  - `superadmin`
- Response

```json
{ "message": "Kategori berhasil dihapus" }
```

> Gagal jika kategori masih memiliki produk.

---

### 🏪 Cabang

#### Daftar Cabang

- URL
  - `/api/branches`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Response

```json
{
  "branches": [{ "id": 1, "name": "string", "address": "string", "phone": "string" }]
}
```

---

#### Buat Cabang

- URL
  - `/api/branches`
- Method
  - `POST`
- Headers
  - `Authorization`: `Bearer <token>`
- Role
  - `superadmin`
- Request Body
  - `name` as `string`
  - `address` as `string`
  - `phone` as `string`
- Response

```json
{ "message": "Cabang berhasil dibuat", "id": 3 }
```

---

#### Update Cabang

- URL
  - `/api/branches/:id`
- Method
  - `PUT`
- Headers
  - `Authorization`: `Bearer <token>`
- Role
  - `admin` (cabang sendiri), `superadmin`
- Request Body — field yang ingin diubah
  - `name` as `string`
  - `address` as `string`
  - `phone` as `string`
- Response

```json
{ "message": "Cabang berhasil diperbarui" }
```

---

### 🧾 Transaksi

#### Daftar Transaksi

- URL
  - `/api/transactions`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Query Params
  - `branch_id`, `user_id`, `payment_status`
  - `start_date`, `end_date` — format `YYYY-MM-DD`
- Response

```json
{
  "transactions": [
    {
      "id": 1,
      "uuid": "string",
      "total_amount": 30000,
      "discount": 0,
      "final_amount": 30000,
      "payment_status": "paid",
      "created_at": "2025-01-01T10:00:00"
    }
  ]
}
```

---

#### Buat Transaksi

- URL
  - `/api/transactions`
- Method
  - `POST`
- Headers
  - `Authorization`: `Bearer <token>`
- Request Body
  - `branch_id` as `number`
  - `items` as `array` — `[{ "product_id": 1, "qty": 2, "price": 15000 }]`
  - `discount` as `number`
  - `payment_method` as `string` — `cash | transfer | e-wallet | card`
  - `payment_amount` as `number`
- Response

```json
{
  "transactionId": 42,
  "message": "Transaksi berhasil dibuat"
}
```

> Validasi stok sebelum commit. Pengurangan stok dilakukan secara atomik. Mencatat pergerakan stok. Mengirim event `transaction-created`, `payment-completed`, `product-updated` via Socket.IO.

---

### 📊 Dashboard

#### Statistik Dashboard

- URL
  - `/api/dashboard`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Response

```json
{
  "todayRevenue": 500000,
  "todayTransactions": 12,
  "monthlyRevenue": 15000000,
  "monthlyTransactions": 320,
  "lowStockCount": 3,
  "outOfStockCount": 1,
  "recentTransactions": []
}
```

> Data otomatis difilter berdasarkan cabang untuk role `admin` dan `karyawan`.

---

### 🎟️ Voucher

#### Validasi Voucher

- URL
  - `/api/vouchers/validate/:code`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Response

```json
{
  "voucher": {
    "id": 1,
    "code": "HEMAT10",
    "discount_type": "percent",
    "discount_value": 10,
    "valid_to": "2025-12-31",
    "is_active": 1
  }
}
```

---

#### Buat Voucher

- URL
  - `/api/vouchers`
- Method
  - `POST`
- Headers
  - `Authorization`: `Bearer <token>`
- Role
  - `admin`, `superadmin`
- Request Body
  - `code` as `string`
  - `description` as `string` — opsional
  - `discount_type` as `string` — `percent | fixed`
  - `discount_value` as `number`
  - `valid_from` as `string` — format `YYYY-MM-DD`, opsional
  - `valid_to` as `string` — format `YYYY-MM-DD`, opsional
  - `is_active` as `number` — `1` atau `0`
  - `target_type` as `string` — `product | categories | null`
  - `target_id` as `number` — opsional
- Response

```json
{ "message": "Voucher berhasil dibuat", "id": 5 }
```

---

### 📈 Analitik

> Semua endpoint analitik membutuhkan role `superadmin`.

#### Ringkasan KPI

- URL
  - `/api/analytics/summary`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Response

```json
{
  "todayRevenue": 500000,
  "monthlyRevenue": 15000000,
  "allTimeRevenue": 200000000
}
```

---

#### Tren Pendapatan Harian

- URL
  - `/api/analytics/revenue-trend`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Query Params
  - `days` — jumlah hari ke belakang, maks 90, default 30
- Response

```json
{
  "trend": [{ "date": "2025-01-01", "revenue": 500000 }]
}
```

---

#### Pendapatan per Cabang

- URL
  - `/api/analytics/branch-revenue`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Query Params
  - `date` — format `YYYY-MM-DD`
- Response

```json
{
  "branches": [{ "branch_id": 1, "name": "Cabang A", "revenue": 300000 }]
}
```

---

#### Kategori Terlaris

- URL
  - `/api/analytics/category-sales`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Query Params
  - `days` — maks 90, default 30
- Response

```json
{
  "categories": [{ "name": "Minuman", "total_qty": 150 }]
}
```

---

#### Produk Terlaris

- URL
  - `/api/analytics/top-products`
- Method
  - `GET`
- Headers
  - `Authorization`: `Bearer <token>`
- Query Params
  - `days` — maks 90, default 30
  - `limit` — maks 20
- Response

```json
{
  "products": [{ "id": 1, "name": "Teh Botol", "total_qty": 80 }]
}
```

---

### ⚡ Socket.IO Events

Hubungkan ke server menggunakan `socket_io_client`. Bergabung ke room cabang untuk menerima update real-time:

```dart
socket.emit('join-branch', branchId);  // bergabung ke room cabang
socket.emit('leave-branch', branchId); // keluar dari room cabang
```

| Event                 | Payload                                       | Dipicu saat                     |
| --------------------- | --------------------------------------------- | ------------------------------- |
| `transaction-created` | objek transaksi                               | Transaksi baru dibuat           |
| `payment-completed`   | `{ transactionId, method, amount, branchId }` | Pembayaran selesai              |
| `product-created`     | objek produk                                  | Produk baru ditambahkan         |
| `product-updated`     | objek produk                                  | Produk diedit atau stok berubah |
| `product-deleted`     | `{ id }`                                      | Produk dihapus                  |
| `server-info`         | status server                                 | Setiap 10 detik                 |

> Gunakan `branch_id = 0` untuk menerima event dari semua cabang (superadmin).

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
