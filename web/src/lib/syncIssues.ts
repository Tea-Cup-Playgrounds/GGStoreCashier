// Plain-language descriptions of the differences the API notes on an offline sale
// (sales.sync_flags.issues, see API/src/routes/sales.js).
import type { SyncIssue } from '../api/types';
import { formatDateTime, formatRp } from './format';

export function describeSyncIssue(issue: SyncIssue): string {
  const name = issue.name ?? `barang #${issue.variant_id ?? '?'}`;
  switch (issue.code) {
    case 'negative_stock':
      return `Stok ${name} jadi ${issue.qty_after} — di sistem sudah habis saat transaksi ini masuk. Hitung ulang stok fisiknya.`;
    case 'price_changed':
      return `Harga ${name}: dibayar ${formatRp(issue.charged)}, harga katalog sekarang ${formatRp(issue.catalog)}.`;
    case 'below_min_price':
      return `Harga ${name} ${formatRp(issue.charged)} di bawah harga minimum ${formatRp(issue.min)}.`;
    case 'inactive_product':
      return `${name} sudah dinonaktifkan di katalog.`;
    case 'manual_discount':
      return `Diskon manual ${formatRp(issue.amount)}${issue.name ? ` pada ${issue.name}` : ''} tanpa izin memberi diskon.`;
    case 'voucher_invalid':
      return `Voucher ${issue.voucher_code} tidak berlaku pada tanggal transaksi (kedaluwarsa atau nonaktif).`;
    case 'voucher_unknown':
      return `Kode voucher ${issue.voucher_code} tidak dikenal.`;
    case 'voucher_not_applicable':
      return `Voucher ${issue.voucher_code} tidak berlaku untuk barang di transaksi ini.`;
    case 'discount_differs':
      return `Diskon yang diberikan ${formatRp(issue.charged)}, menurut aturan voucher ${formatRp(issue.expected)}.`;
    case 'shift_closed':
      return 'Shift kasir sudah ditutup sebelum transaksi ini masuk: hitungan kas saat tutup shift belum termasuk transaksi ini.';
    case 'shift_missing':
      return 'Shift kasir tidak ditemukan; transaksi dicatat tanpa shift.';
    case 'payment_method_inactive':
      return `Metode pembayaran ${issue.name} sudah dinonaktifkan.`;
    case 'tax_assumed_inclusive':
      return 'Harga dicatat sudah termasuk PPN (perangkat yang offline tidak tahu pengaturan pajak).';
    case 'underpaid_adjusted':
      return `Dibayar ${formatRp(issue.amount)} lebih sedikit dari harga sekarang; selisihnya dicatat sebagai diskon.`;
    case 'total_differs':
      return `Total di perangkat ${formatRp(issue.charged)}, tercatat ${formatRp(issue.recorded)}.`;
    case 'cashier_unverified':
      return `Kasir #${issue.cashier_id} tidak dikenali atau tidak boleh berjualan di lokasi ini; dicatat atas nama pengunggah.`;
    case 'late':
      return `Transaksi baru masuk ${issue.hours} jam setelah terjadi.`;
    case 'clock_ahead':
      return `Jam perangkat lebih cepat (${formatDateTime(issue.reported)}); waktu transaksi diganti waktu diterima.`;
    default:
      return issue.code;
  }
}
