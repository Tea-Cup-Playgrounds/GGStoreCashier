import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';

class RefreshButton extends StatelessWidget {
  final VoidCallback onRefresh;
  final AnimationController refreshController;
  const RefreshButton(
      {super.key, required this.onRefresh, required this.refreshController});

  @override
  Widget build(BuildContext context) {
    return IconButton(
        onPressed: refreshController.isAnimating ? null : onRefresh,
        icon: RotationTransition(
          turns: refreshController,
          child: const Icon(
            Icons.refresh,
            color: AppTheme.mutedForeground,
          ),
        ));
  }
}
