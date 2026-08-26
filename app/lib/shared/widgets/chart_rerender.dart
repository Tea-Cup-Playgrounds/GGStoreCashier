import 'dart:async';
import 'package:flutter/material.dart';

/// Wraps any chart widget and forces a canvas rebuild every [interval].
///
/// fl_chart draws on a `CustomPaint` canvas. When data updates via socket
/// events the canvas can stale or glitch if the surrounding widget tree does
/// not rebuild. This widget drives a controlled 500 ms tick that gives the
/// canvas a fresh `repaintBoundary`, eliminating flickering artefacts without
/// recomputing heavy layout.
///
/// Usage:
/// ```dart
/// ChartRerender(
///   child: LineChart(data),
/// )
/// ```
class ChartRerender extends StatefulWidget {
  const ChartRerender({
    super.key,
    required this.child,
    this.interval = const Duration(milliseconds: 500),
  });

  final Widget child;

  /// How often the canvas is nudged. Default is 500 ms.
  final Duration interval;

  @override
  State<ChartRerender> createState() => _ChartRerenderState();
}

class _ChartRerenderState extends State<ChartRerender> {
  Timer? _timer;

  /// Monotonically incrementing counter — used as a key so the paint
  /// boundary is always considered "new" by the framework.
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary with a changing key forces the canvas layer to be
    // composited fresh on each tick without a full widget rebuild.
    return RepaintBoundary(
      key: ValueKey(_tick),
      child: widget.child,
    );
  }
}

/// A convenience wrapper that rebuilds its child on a 500 ms timer.
/// Use this around any widget that reads from a store that updates at 500 ms
/// (e.g., live transaction feed, stock cards).
class LiveRerender extends StatefulWidget {
  const LiveRerender({
    super.key,
    required this.builder,
    this.interval = const Duration(milliseconds: 500),
  });

  final WidgetBuilder builder;
  final Duration interval;

  @override
  State<LiveRerender> createState() => _LiveRerenderState();
}

class _LiveRerenderState extends State<LiveRerender> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
