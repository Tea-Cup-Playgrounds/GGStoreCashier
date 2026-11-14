// Lays a receipt out as fixed-width text rows. The same rows are sent to the printer (esc_pos.dart)
// and drawn on screen (ReceiptPreview), so what the editor and the printer page show is what prints.

import 'package:intl/intl.dart';

import 'receipt.dart';
import 'receipt_config.dart';

enum RowAlign { left, center, right }

sealed class ReceiptRow {
  const ReceiptRow();
}

class TextRow extends ReceiptRow {
  final String text;
  final RowAlign align;
  final bool bold;

  /// Double width and height: half as many characters fit on a line.
  final bool large;

  const TextRow(this.text, {this.align = RowAlign.left, this.bold = false, this.large = false});

  @override
  String toString() => text;
}

class DividerRow extends ReceiptRow {
  const DividerRow();
}

/// A QR code holding [data] (the sale number), printed centered.
class QrRow extends ReceiptRow {
  final String data;
  const QrRow(this.data);
}

class ReceiptLayout {
  static final _date = DateFormat('dd-MM-yyyy HH:mm');

  /// "85.000" or "85.000,50": thousands with dots, cents only when there are any.
  static String money(double value) {
    final cents = (value.abs() * 100).round();
    final whole = (cents ~/ 100).toString();
    final buf = StringBuffer(value < 0 && cents > 0 ? '-' : '');
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write('.');
      buf.write(whole[i]);
    }
    if (cents % 100 != 0) buf.write(',${(cents % 100).toString().padLeft(2, '0')}');
    return buf.toString();
  }

  static String _qty(double qty) => qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();

  /// Splits [text] into lines of at most [width] characters, at spaces where possible.
  static List<String> wrap(String text, int width) {
    final lines = <String>[];
    for (final paragraph in text.split('\n')) {
      var line = '';
      for (var word in paragraph.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
        while (word.length > width) {
          if (line.isNotEmpty) {
            lines.add(line);
            line = '';
          }
          lines.add(word.substring(0, width));
          word = word.substring(width);
        }
        if (line.isEmpty) {
          line = word;
        } else if (line.length + 1 + word.length <= width) {
          line = '$line $word';
        } else {
          lines.add(line);
          line = word;
        }
      }
      if (line.isNotEmpty) lines.add(line);
    }
    return lines;
  }

  /// [left] and [right] on one line, right-aligned; when they don't fit, [left] wraps and
  /// [right] goes on a line of its own.
  static List<String> pair(String left, String right, int width) {
    if (left.length + 1 + right.length <= width) {
      return ['$left${' ' * (width - left.length - right.length)}$right'];
    }
    return [...wrap(left, width), right.padLeft(width)];
  }

  static List<ReceiptRow> build(ReceiptData r, ReceiptConfig c) {
    final width = c.charsPerLine;
    final rows = <ReceiptRow>[];
    var metaDone = false;

    void text(String s, {RowAlign align = RowAlign.left, bool bold = false}) =>
        rows.add(TextRow(s, align: align, bold: bold));
    void pairRow(String left, String right, {bool bold = false, bool large = false}) {
      for (final line in pair(left, right, large ? width ~/ 2 : width)) {
        rows.add(TextRow(line, bold: bold, large: large));
      }
    }

    void centered(String s, {bool bold = false, bool large = false}) {
      for (final line in wrap(s, large ? width ~/ 2 : width)) {
        rows.add(TextRow(line, align: RowAlign.center, bold: bold, large: large));
      }
    }

    void divider() {
      if (rows.isNotEmpty && rows.last is! DividerRow) rows.add(const DividerRow());
    }

    // Number, date, cashier: once, before the first section about the sale itself.
    void meta() {
      if (metaDone) return;
      metaDone = true;
      divider();
      if (r.copy) centered('** SALINAN **', bold: true);
      if (r.offline) centered('(transaksi offline)');
      if (c.showTransactionId) {
        pairRow('No', r.number ?? 'menunggu server');
        if (r.number == null && r.reference != null) pairRow('Ref', r.reference!);
      }
      if (c.showDateTime) pairRow('Tanggal', _date.format(r.date));
      if (c.showCashierName && r.cashier != null && r.cashier!.isNotEmpty) pairRow('Kasir', r.cashier!);
      if (r.customer != null && r.customer!.isNotEmpty) pairRow('Pelanggan', r.customer!);
    }

    for (final section in c.sections) {
      switch (section) {
        case 'header':
          centered(c.storeName, bold: true, large: true);
          final branch = c.branch.isNotEmpty ? c.branch : r.locationName;
          if (branch != null && branch.isNotEmpty) centered(branch);
        case 'contact':
          final address = c.address.isNotEmpty ? c.address : r.locationAddress;
          final phone = c.phone.isNotEmpty ? c.phone : r.locationPhone;
          if (address != null && address.isNotEmpty) centered(address);
          if (phone != null && phone.isNotEmpty) centered('Telp. $phone');
        case 'divider':
          divider();
        case 'items':
          meta();
          divider();
          for (final item in r.items) {
            for (final line in wrap(item.name, width)) {
              text(line);
            }
            pairRow('  ${_qty(item.qty)} x ${money(item.unitPrice)}', money(item.qty * item.unitPrice));
            if (item.discount > 0 && c.discountEnabled) pairRow('  ${c.discountLabel}', '-${money(item.discount)}');
          }
        case 'totals':
          meta();
          divider();
          pairRow('Subtotal', money(r.subtotal));
          if (r.discount > 0) {
            if (r.voucherCode != null && c.voucherEnabled) {
              pairRow('${c.voucherLabel} ${r.voucherCode}', '-${money(r.discount)}');
            } else if (c.discountEnabled) {
              pairRow(c.discountLabel, '-${money(r.discount)}');
            }
          }
          final tax = r.tax;
          // Tax added on top (prices exclude PPN) shows before the total; otherwise it is inside it.
          final taxOnTop = tax != null && tax > 0 && (r.subtotal - r.discount + tax - r.total).abs() < 0.01;
          if (c.taxEnabled && taxOnTop) pairRow(c.taxLabel, money(tax));
          pairRow('TOTAL', money(r.total), bold: true, large: true);
          if (c.taxEnabled && !taxOnTop) {
            if (tax != null && tax > 0) {
              pairRow('Termasuk ${c.taxLabel}', money(tax));
            } else if (tax == null) {
              text('Harga sudah termasuk ${c.taxLabel}');
            }
          }
        case 'payment':
          meta();
          for (final p in r.payments) {
            pairRow(p.name, money(p.amount));
            if (p.reference != null && p.reference!.isNotEmpty) pairRow('  Ref', p.reference!);
          }
          if (r.change > 0) pairRow('Kembali', money(r.change));
        case 'barcode':
          meta();
          if (r.number != null) {
            divider();
            rows.add(QrRow(r.number!));
            centered(r.number!);
          }
        case 'footer':
          meta();
          if (c.footer.trim().isNotEmpty) {
            divider();
            centered(c.footer);
          }
        default:
          break; // 'logo' and unknown sections are not printed
      }
    }
    meta();
    while (rows.isNotEmpty && rows.last is DividerRow) {
      rows.removeLast();
    }
    return rows;
  }

  /// A receipt with sample data, for the test print and the editor preview.
  static ReceiptData sample({DateTime? date}) => ReceiptData(
        number: 'INV-BR01-261114-0001',
        date: date ?? DateTime.now(),
        cashier: 'Kasir Cabang Satu',
        locationName: 'Cabang 1',
        items: const [
          ReceiptItem(name: 'Charger 20W USB-C', qty: 1, unitPrice: 85000, total: 85000),
          ReceiptItem(name: 'Tempered Glass', qty: 2, unitPrice: 25000, discount: 5000, total: 45000),
        ],
        subtotal: 135000,
        discount: 5000,
        tax: 12882.88,
        total: 130000,
        payments: const [ReceiptPayment(name: 'Tunai', amount: 150000)],
        change: 20000,
      );
}
