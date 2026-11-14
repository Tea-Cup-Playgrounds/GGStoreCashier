import 'package:material_ui/material_ui.dart';

import '../../domain/receipt_layout.dart';

/// Draws receipt rows as they print: fixed-width text on white paper, [charsPerLine] wide.
class ReceiptPreview extends StatelessWidget {
  final List<ReceiptRow> rows;
  final int charsPerLine;

  const ReceiptPreview({super.key, required this.rows, required this.charsPerLine});

  static const _font = 11.0;

  @override
  Widget build(BuildContext context) {
    // Monospace glyphs are ~0.6em wide; size the paper to the printer's line.
    final paperWidth = charsPerLine * _font * 0.62 + 28;
    const style = TextStyle(fontFamily: 'monospace', fontSize: _font, height: 1.35, color: Colors.black);

    return Center(
      child: Container(
        width: paperWidth,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: paperWidth - 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in rows)
                  switch (row) {
                    TextRow() => Text(
                        row.text,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: switch (row.align) {
                          RowAlign.left => TextAlign.left,
                          RowAlign.center => TextAlign.center,
                          RowAlign.right => TextAlign.right,
                        },
                        style: style.copyWith(
                          fontWeight: row.bold ? FontWeight.w700 : FontWeight.w400,
                          fontSize: row.large ? _font * 2 : _font,
                        ),
                      ),
                    DividerRow() => Text('-' * charsPerLine, maxLines: 1, softWrap: false, style: style),
                    QrRow() => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 3)),
                            alignment: Alignment.center,
                            child: const Icon(Icons.qr_code_2, size: 56, color: Colors.black),
                          ),
                        ),
                      ),
                  },
              ],
            ),
          ),
        ),
      ),
    );
  }
}
