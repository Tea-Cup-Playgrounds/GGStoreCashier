## Skema Database

Berikut adalah tabel-tabel yang digunakan beserta relasinya:

| Tabel               | Deskripsi                                                             |
| ------------------- | --------------------------------------------------------------------- |
| `users`             | Data pengguna — nama, username, password (bcrypt), role, dan cabang.  |
| `branches`          | Data cabang toko — nama, alamat, dan nomor telepon.                   |
| `categories`        | Kategori produk — nama, deskripsi, dan gambar.                        |
| `products`          | Data produk — nama, barcode, harga jual, stok, gambar, dan cabang.    |
| `transactions`      | Header transaksi — user, cabang, total, diskon, status pembayaran.    |
| `transaction_items` | Detail item per transaksi — produk, qty, harga, subtotal.             |
| `payments`          | Data pembayaran per transaksi — metode dan jumlah.                    |
| `stock_movements`   | Riwayat pergerakan stok (masuk/keluar) per produk per cabang.         |
| `vouchers`          | Data voucher diskon — kode, tipe diskon, nilai, masa berlaku, target. |
| `returns`           | Data retur produk dari transaksi.                                     |
| `absensi`           | Data absensi karyawan per cabang.                                     |

**Relasi utama:**

- `users` → `branches` (many-to-one)
- `products` → `branches`, `categories` (many-to-one)
- `transactions` → `users`, `branches` (many-to-one)
- `transaction_items` → `transactions`, `products` (many-to-one)
- `payments` → `transactions` (many-to-one, CASCADE delete)
- `stock_movements` → `products`, `branches` (many-to-one)

---
