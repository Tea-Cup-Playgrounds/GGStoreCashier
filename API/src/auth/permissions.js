// Every permission the API checks. Roles (stored in the database) are sets of these keys.
// Adding a key here does not grant it to anyone except the owner role; grant it to system
// roles with a migration.
const PERMISSIONS = {
    'sales.create': { group: 'sales', description: 'Membuat transaksi penjualan' },
    'sales.void': { group: 'sales', description: 'Membatalkan transaksi' },
    'sales.discount_override': { group: 'sales', description: 'Memberi diskon di luar batas' },
    'sales.price_override': { group: 'sales', description: 'Menjual di bawah harga minimum' },
    'vouchers.manage': { group: 'sales', description: 'Mengelola voucher diskon' },

    'cash_session.open': { group: 'cash_session', description: 'Membuka shift kasir' },
    'cash_session.close': { group: 'cash_session', description: 'Menutup shift kasir' },
    'cash_session.view_all': { group: 'cash_session', description: 'Melihat semua shift di lokasi' },

    'catalog.view': { group: 'catalog', description: 'Melihat katalog produk' },
    'catalog.manage': { group: 'catalog', description: 'Mengelola produk, varian, kategori, merek' },
    'prices.manage_location': { group: 'catalog', description: 'Mengatur harga jual khusus lokasi' },

    'stock.view': { group: 'stock', description: 'Melihat stok' },
    'stock.adjust': { group: 'stock', description: 'Penyesuaian stok manual' },
    'stock.opname': { group: 'stock', description: 'Melakukan dan menyetujui stok opname' },
    'units.register': { group: 'stock', description: 'Mendaftarkan IMEI/serial unit' },
    'units.register_at_pos': { group: 'stock', description: 'Mendaftarkan IMEI baru saat checkout' },

    'transfers.create': { group: 'transfers', description: 'Membuat draf transfer stok' },
    'transfers.send': { group: 'transfers', description: 'Mengirim transfer stok' },
    'transfers.receive': { group: 'transfers', description: 'Menerima transfer stok' },

    'purchases.manage': { group: 'purchasing', description: 'Mengelola penerimaan barang dan pembayaran supplier' },
    'suppliers.manage': { group: 'purchasing', description: 'Mengelola data supplier' },

    'customers.manage': { group: 'customers', description: 'Mengelola data pelanggan' },

    'accounting.view': { group: 'accounting', description: 'Melihat akun dan jurnal' },
    'accounting.post_manual': { group: 'accounting', description: 'Membuat jurnal manual' },
    'accounting.close_period': { group: 'accounting', description: 'Menutup periode akuntansi' },

    'reports.view_location': { group: 'reports', description: 'Melihat laporan lokasi sendiri' },
    'reports.view_all': { group: 'reports', description: 'Melihat laporan semua lokasi' },

    'users.manage': { group: 'admin', description: 'Mengelola pengguna dan penugasan lokasi' },
    'roles.manage': { group: 'admin', description: 'Mengelola role dan izin' },
    'locations.manage': { group: 'admin', description: 'Mengelola cabang dan gudang' },
    'settings.manage': { group: 'admin', description: 'Mengelola pengaturan aplikasi' },

    'data.import': { group: 'data', description: 'Impor data' },
    'data.export': { group: 'data', description: 'Ekspor data' },
};

const OWNER_ROLE_CODE = 'owner';

const isValidPermission = (key) => Object.prototype.hasOwnProperty.call(PERMISSIONS, key);

module.exports = {
    PERMISSIONS,
    OWNER_ROLE_CODE,
    isValidPermission,
};
