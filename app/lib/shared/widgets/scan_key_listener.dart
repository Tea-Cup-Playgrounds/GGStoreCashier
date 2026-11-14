import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Picks up codes from a USB or Bluetooth barcode scanner. Such scanners act as a keyboard: they
/// type the code very quickly and press Enter. While no text field has focus, those keystrokes are
/// collected here and the code is passed to [onScan]; typing into fields is left alone (a field's
/// own submit handles a scan into it).
///
/// Only active while its page is the visible one (not covered by another route or tab).
class ScanKeyListener extends StatefulWidget {
  final Widget child;
  final ValueChanged<String> onScan;

  /// Keys further apart than this belong to a person typing, not a scanner.
  final Duration maxGap;

  const ScanKeyListener({super.key, required this.child, required this.onScan, this.maxGap = const Duration(milliseconds: 80)});

  @override
  State<ScanKeyListener> createState() => _ScanKeyListenerState();
}

class _ScanKeyListenerState extends State<ScanKeyListener> {
  final _buffer = StringBuffer();
  DateTime? _lastKey;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Set in build: false on an inactive tab or under a pushed page, sheet or dialog.
  bool _visible = true;

  bool get _textFieldFocused {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    return focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted || !_visible || _textFieldFocused) {
      if (event is KeyDownEvent) _buffer.clear();
      return false;
    }
    final now = DateTime.now();
    if (_lastKey != null && now.difference(_lastKey!) > widget.maxGap) _buffer.clear();
    _lastKey = now;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString();
      _buffer.clear();
      if (code.length >= 3) {
        widget.onScan(code);
        return true;
      }
      return false;
    }
    final char = event.character;
    if (char != null && char.length == 1 && char.codeUnitAt(0) >= 0x20) _buffer.write(char);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    _visible = TickerMode.valuesOf(context).enabled && (ModalRoute.of(context)?.isCurrent ?? true);
    return widget.child;
  }
}
