import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A self-updating date + time display.
/// Updates every second.
class LiveClock extends StatefulWidget {
  final TextStyle? dateStyle;
  final TextStyle? timeStyle;
  final bool showDate;
  final bool showTime;

  const LiveClock({
    super.key,
    this.dateStyle,
    this.timeStyle,
    this.showDate = true,
    this.showTime = true,
  });

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  late DateTime _now;
  late Timer _timer;

  static final _dateFmt = DateFormat('EEEE, dd MMM yyyy'); // Monday, 03 Apr 2026
  static final _timeFmt = DateFormat('HH:mm:ss');          // 14:32:07

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final defaultDateStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: cs.onSurface.withOpacity(0.55),
        );
    final defaultTimeStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showTime)
          Text(_timeFmt.format(_now),
              style: widget.timeStyle ?? defaultTimeStyle),
        if (widget.showDate)
          Text(_dateFmt.format(_now),
              style: widget.dateStyle ?? defaultDateStyle),
      ],
    );
  }
}
