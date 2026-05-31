# Panduan Setup Ngrok

Ngrok membuat URL publik yang menghubungkan ke API lokal kamu, sehingga kamu bisa menguji aplikasi Flutter di perangkat fisik atau berbagi API dengan orang lain.

## Kenapa Pakai Ngrok?

- **Testing di Perangkat Fisik** — Uji di HP sungguhan tanpa harus terhubung ke WiFi yang sama
- **Testing Jarak Jauh** — Bagikan API ke anggota tim atau tester
- **Webhook Testing** — Terima webhook dari layanan eksternal
- **HTTPS** — Dapatkan URL HTTPS gratis untuk testing koneksi aman

---

## Langkah Setup

### 1. Buat Akun Ngrok

1. Buka [https://ngrok.com/](https://ngrok.com/)
2. Daftar akun gratis
3. Setelah login, buka halaman "Your Authtoken": [https://dashboard.ngrok.com/get-started/your-authtoken](https://dashboard.ngrok.com/get-started/your-authtoken)
4. Salin authtoken kamu (contoh: `2abc123def456ghi789jkl0mnop1qrs_2tuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ`)

---

### 2. Tambahkan Authtoken ke `.env`

Buka file `.env` di root proyek dan tambahkan:

```env
# Database
DB_HOST=localhost
DB_USER=root
DB_PASSWORD=your_password
DB_NAME=gg_store

# API
PORT=3000
JWT_SECRET=your_secret_key

# Ngrok
NGROK_AUTHTOKEN=2abc123def456ghi789jkl0mnop1qrs_2tuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ

# API Timeout
API_TIMEOUT=30000
```

---

### 3. Jalankan Server

```bash
npm run dev
```

Kamu akan melihat output seperti ini:

```
Server running on port 3000
Socket.IO enabled for real-time updates
API Docs: http://localhost:3000/api/docs

ngrok public URL : https://abc123.ngrok.io
API Docs         : https://abc123.ngrok.io/api/docs

✅ app/.env updated with ngrok URL
```

Server secara otomatis akan:

1. Memulai tunnel ngrok
2. Mendapatkan URL publik
3. Menulis URL tersebut ke `app/.env` agar Flutter menggunakannya

---

### 4. Verifikasi

**Test di browser:**

```
https://abc123.ngrok.io/api/health
```

Seharusnya mengembalikan:

```json
{
  "status": "OK",
  "message": "Server is running"
}
```

**Cek konfigurasi Flutter:**

```bash
cat app/.env
```

Seharusnya menampilkan:

```env
API_BASE_URL=https://abc123.ngrok.io
API_TIMEOUT=30000
```

---

### 5. Jalankan Flutter

Setelah server berjalan, jalankan aplikasi Flutter — ia akan terhubung via URL ngrok:

```bash
cd app
fvm flutter run
```

Atau gunakan VS Code Run & Debug → "Flutter (Mobile App via FVM)"

---

## Tanpa Ngrok (Emulator Saja)

Jika kamu tidak menambahkan `NGROK_AUTHTOKEN`, server akan:

1. Melewati tunnel ngrok
2. Menulis `http://10.0.2.2:3000` ke `app/.env` (IP localhost khusus emulator Android)
3. Tetap berjalan normal untuk testing di emulator

```bash
npm run dev
```

Output:

```
Server running on port 3000
⚠️  NGROK_AUTHTOKEN not set — skipping ngrok tunnel
✅ app/.env updated with emulator URL: http://10.0.2.2:3000
```

---

## Batas Ngrok Tier Gratis

- **1 proses ngrok** aktif dalam satu waktu
- **40 koneksi/menit**
- **URL acak** setiap kali restart (contoh: `https://abc123.ngrok.io` berubah setiap restart)
- **Sesi 2 jam** — tunnel otomatis tutup setelah 2 jam, restart untuk mendapatkan URL baru

### Paket Berbayar ($8/bulan ke atas):

- Subdomain kustom (contoh: `https://myapp.ngrok.io`)
- Sesi lebih lama
- Lebih banyak koneksi
- Domain yang bisa dipesan

---

## Troubleshooting

### Error "Invalid authtoken"

- Pastikan kamu menyalin token lengkap dari dashboard ngrok
- Pastikan tidak ada spasi ekstra di file `.env`
- Token harus satu baris panjang tanpa baris baru

### URL ngrok berubah setiap restart

- Ini normal di tier gratis
- Server otomatis memperbarui `app/.env` setiap kali
- Cukup restart aplikasi Flutter untuk mengambil URL baru

### Flutter masih terhubung ke URL lama

1. Hentikan aplikasi Flutter
2. Cek `app/.env` sudah berisi URL ngrok yang baru
3. Restart Flutter (hot reload tidak akan membaca perubahan `.env`)

### "Tunnel not found" di browser

- Pastikan server sedang berjalan (`npm run dev`)
- Cek konsol untuk URL ngrok terbaru
- Coba URL di jendela incognito (beberapa browser menyimpan cache redirect)

### Error rate limit

- Tier gratis memiliki batas 40 koneksi/menit
- Jika mencapai batas, tunggu sebentar atau upgrade ke paket berbayar
- Kurangi pemanggilan API yang tidak perlu di aplikasi Flutter

---

## Alternatif: Gunakan IP Lokal (Tanpa Ngrok)

Jika kamu hanya ingin testing di perangkat fisik yang terhubung ke WiFi yang sama:

1. Cari IP lokal komputermu:

   ```bash
   # Windows
   ipconfig
   # Cari IPv4 Address (contoh: 192.168.1.100)

   # Mac/Linux
   ifconfig | grep "inet "
   ```

2. Edit `app/.env` secara manual:

   ```env
   API_BASE_URL=http://192.168.1.100:3000
   API_TIMEOUT=30000
   ```

3. Pastikan Windows Firewall mengizinkan port 3000

4. Jalankan server tanpa ngrok:

   ```bash
   npm run dev
   ```

5. Hubungkan HP ke WiFi yang sama dan jalankan aplikasi Flutter

---

## Ringkasan

**Dengan Ngrok:**

- Tambahkan `NGROK_AUTHTOKEN` ke `.env`
- Jalankan `npm run dev`
- Server otomatis memperbarui `app/.env` dengan URL publik
- Bisa diakses dari perangkat mana saja, di mana saja

**Tanpa Ngrok:**

- Jangan tambahkan `NGROK_AUTHTOKEN`
- Jalankan `npm run dev`
- Server otomatis memperbarui `app/.env` dengan `10.0.2.2:3000`
- Hanya bisa digunakan di emulator

Server menangani semuanya secara otomatis — kamu hanya perlu menambahkan authtoken jika ingin menggunakan ngrok.
