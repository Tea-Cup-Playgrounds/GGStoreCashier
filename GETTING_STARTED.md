# Panduan Memulai — Langkah demi Langkah

## Setup Pertama Kali

### 1. Install Dependensi

**Install paket Node:**

```bash
npm install
```

**Install dependensi Flutter:**

```bash
cd app
fvm flutter pub get
cd ..
```

---

### 2. Setup Database

- Buat database MySQL kosong
- Perbarui `.env` dengan kredensial database kamu
- Jalankan `npm run migrate` untuk membuat semua tabel (lihat bagian migrasi di `README.md`)

---

### 3. Buat File Environment

**File `.env` di root proyek:**

```env
# Database
DB_HOST=localhost
DB_USER=root
DB_PASSWORD=your_password
DB_NAME=gg_store

# API
PORT=3000
JWT_SECRET=your_secret_key_here

# Ngrok (untuk menghubungkan Flutter ke API)
NGROK_API_URL=(Link NGROK Ada, ambil dari website ngroknya, settingnya liat tutorial)
NGROK_API_TIMEOUT=30000
```

**File `.env` Flutter** (akan dibuat otomatis oleh script sync-env):

```env
# File ini ada di app/.env
# Dibuat otomatis saat kamu menjalankan npm run dev
API_BASE_URL=http://10.0.2.2:3000
API_TIMEOUT=30000
```

---

## Menjalankan Proyek

### Opsi 1: Jalankan Semuanya Sekaligus (Direkomendasikan)

1. **Buka Android Emulator** dari Android Studio, atau lewat terminal:

   ```bash
   # Lihat daftar emulator yang tersedia
   emulator -list-avds

   # Jalankan emulator
   emulator -avd Pixel_5_API_34
   ```

2. **Buka VS Code** dan pergi ke panel Run & Debug (Ctrl+Shift+D)

3. **Pilih "Full Stack (Flutter + API)"** dari dropdown

4. **Tekan F5** atau klik tombol play hijau

   Ini akan secara otomatis:
   - Menjalankan Express API dengan nodemon (hot reload)
   - Memulai tunnel ngrok (jika sudah dikonfigurasi)
   - Menyinkronkan URL API ke `.env` Flutter
   - Meluncurkan aplikasi Flutter di emulator

---

### Opsi 2: Jalankan Terpisah (Untuk Debugging)

**Terminal 1 — Jalankan API:**

```bash
npm run dev
```

Tunggu hingga muncul:

```
Server running on port 3000
Ngrok tunnel: https://xxxx-xx-xx-xx-xx.ngrok.io
```

**Terminal 2 — Jalankan Flutter: (bisa langsung run lewat debugging vscode dsb, ini optional )**

```bash
cd app
fvm flutter run
```

Atau gunakan VS Code:

- Run & Debug → "Flutter (Mobile App via FVM)" → F5

---

### Opsi 3: Mode Produksi

**Jalankan API saja:**

```bash
npm start
```

**Build APK Flutter:**

```bash
cd app
fvm flutter build apk --release
```

---

## Menghubungkan Flutter ke API

### Untuk Emulator Android

API berjalan di `localhost:3000` di komputermu, tapi emulator melihatnya sebagai:

- `10.0.2.2:3000` (IP khusus emulator Android untuk localhost)

Perbarui `app/.env`:

```env
API_BASE_URL=http://10.0.2.2:3000
API_TIMEOUT=30000
```

---

### Untuk Perangkat Fisik (WiFi yang Sama)

1. Cari IP lokal komputermu:

   ```bash
   # Windows
   ipconfig
   # Cari IPv4 Address (contoh: 192.168.1.100)

   # Mac/Linux
   ifconfig
   ```

2. Perbarui `app/.env`:

   ```env
   API_BASE_URL=http://192.168.1.100:3000
   API_TIMEOUT=30000
   ```

3. Pastikan firewall mengizinkan port 3000

---

### Menggunakan Ngrok (Testing Jarak Jauh)

Script `npm run dev` secara otomatis:

1. Memulai tunnel ngrok
2. Menyinkronkan URL ngrok ke `app/.env`

Aplikasi Flutter akan terhubung via URL publik ngrok. Lihat [NGROK_SETUP.md](./NGROK_SETUP.md) untuk panduan lengkap.

---

## Troubleshooting

### API tidak mau jalan

```bash
# Cek apakah port 3000 sudah dipakai
# Windows
netstat -ano | findstr :3000

# Matikan proses yang menggunakan port tersebut
taskkill /PID <PID> /F
```

---

### Flutter tidak bisa terhubung ke API

1. Cek `app/.env` sudah berisi `API_BASE_URL` yang benar
2. Untuk emulator, gunakan `http://10.0.2.2:3000`
3. Cek API sudah berjalan — buka `http://localhost:3000` di browser
4. Cek firewall tidak memblokir port 3000

---

### Emulator tidak terdeteksi

```bash
cd app
fvm flutter doctor
fvm flutter devices
```

---

### Hot reload tidak berfungsi

- Untuk API: nodemon seharusnya otomatis restart saat file berubah
- Untuk Flutter: tekan `r` di terminal atau simpan file di VS Code

---

### Error koneksi database

1. Pastikan MySQL sedang berjalan
2. Cek kredensial di `.env`
3. Pastikan database sudah dibuat
4. Cek konfigurasi koneksi di `API/src/db.js`

---

## Shortcut VS Code

| Shortcut        | Fungsi              |
| --------------- | ------------------- |
| `F5`            | Mulai debugging     |
| `Shift+F5`      | Hentikan debugging  |
| `Ctrl+Shift+F5` | Restart debugging   |
| `Ctrl+\``       | Buka/tutup terminal |

---

## Langkah Selanjutnya

1. Buka Android Emulator
2. Tekan F5 di VS Code dengan "Full Stack (Flutter + API)" dipilih
3. Tunggu API dan Flutter selesai start
4. Aplikasi akan otomatis terbuka di emulator

API akan tersedia di `http://localhost:3000` dan aplikasi Flutter akan terhubung ke `http://10.0.2.2:3000`.
