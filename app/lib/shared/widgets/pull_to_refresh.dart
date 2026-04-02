import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A reusable pull-to-refresh wrapper.
/// Wrap any scrollable widget with this to add pull-to-refresh behaviour.
///
/// Example:
/// ```dart
/// PullToRefresh(
///   onRefresh: _loadData,
///   child: ListView(...),
/// )
/// ```
class PullToRefresh extends StatelessWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color = AppTheme.gold,
    this.backgroundColor,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final Color color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: color,
      backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.surface,
      child: child,
    );
  }
}
