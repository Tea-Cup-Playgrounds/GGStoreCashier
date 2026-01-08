import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';

class CustomTitle extends StatelessWidget {
  final String title;
  const CustomTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall!.copyWith(
            fontSize: 16,
          ),
    );
  }
}
