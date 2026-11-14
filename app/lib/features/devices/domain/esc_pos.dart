// ESC/POS bytes for receipt rows. ESC/POS is the command set of almost every thermal receipt
// printer (Epson, Xprinter, EPPOS, Panda, iWare, ...), over Bluetooth, USB or the network.

import 'receipt_layout.dart';

class EscPos {
  static const _esc = 0x1B;
  static const _gs = 0x1D;
  static const _lf = 0x0A;

  /// Printer bytes for [rows] on paper [charsPerLine] wide: initialize, rows, feed, cut.
  /// [openDrawer] first kicks a cash drawer plugged into the printer.
  static List<int> encode(List<ReceiptRow> rows, {required int charsPerLine, bool openDrawer = false, int feedLines = 4, bool cut = true}) {
    final out = <int>[
      _esc, 0x40, // ESC @: initialize
      _esc, 0x74, 0x00, // ESC t 0: code page PC437
    ];
    if (openDrawer) out.addAll([_esc, 0x70, 0x00, 0x19, 0xFA]); // ESC p: pulse drawer pin 2

    for (final row in rows) {
      switch (row) {
        case TextRow():
          out.addAll([_esc, 0x61, row.align.index]); // ESC a n: align
          if (row.bold) out.addAll([_esc, 0x45, 0x01]); // ESC E 1: bold on
          if (row.large) out.addAll([_gs, 0x21, 0x11]); // GS ! 0x11: double width + height
          out.addAll(text(row.text));
          out.add(_lf);
          if (row.large) out.addAll([_gs, 0x21, 0x00]);
          if (row.bold) out.addAll([_esc, 0x45, 0x00]);
        case DividerRow():
          out.addAll([_esc, 0x61, 0x00]);
          out.addAll(text('-' * charsPerLine));
          out.add(_lf);
        case QrRow():
          out.addAll([_esc, 0x61, 0x01]);
          out.addAll(qr(row.data));
          out.add(_lf);
      }
    }
    out.addAll([_esc, 0x61, 0x00]);
    out.addAll([_esc, 0x64, feedLines.clamp(0, 255)]); // ESC d n: feed n lines
    if (cut) out.addAll([_gs, 0x56, 0x42, 0x00]); // GS V 66 0: feed to cutter and partial cut
    return out;
  }

  /// QR code (model 2, error correction M) with modules [size] dots wide.
  static List<int> qr(String data, {int size = 6}) {
    final bytes = text(data);
    final len = bytes.length + 3;
    return [
      _gs, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00, // model 2
      _gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size.clamp(1, 16), // module size
      _gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31, // error correction M
      _gs, 0x28, 0x6B, len & 0xFF, len >> 8, 0x31, 0x50, 0x30, ...bytes, // store data
      _gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30, // print
    ];
  }

  static const _plain = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ù': 'u',
    'ú': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c', 'À': 'A', 'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O',
    'Ú': 'U', 'Ñ': 'N', '–': '-', '—': '-', '‘': "'", '’': "'", '“': '"', '”': '"', '…': '...', '·': '-',
    '×': 'x', '•': '*', ' ': ' ',
  };

  /// Printable bytes for [s]: ASCII as is, common accents and punctuation simplified, anything
  /// else as '?', so a name in another script can't send the printer stray commands.
  static List<int> text(String s) {
    final out = <int>[];
    for (final rune in s.runes) {
      if (rune >= 0x20 && rune < 0x7F) {
        out.add(rune);
      } else {
        final plain = _plain[String.fromCharCode(rune)];
        out.addAll(plain != null ? plain.codeUnits : [0x3F]);
      }
    }
    return out;
  }
}
