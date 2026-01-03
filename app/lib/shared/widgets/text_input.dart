import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';

class TextInput extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final int maxLines;
  final bool readOnly;
  final String? hintText;
  final String? Function(String?)? validator;

  const TextInput(
      {super.key,
      required this.label,
      required this.controller,
      this.validator,
      this.hintText,
      this.onTap,
      this.keyboardType = TextInputType.text,
      this.maxLines = 1,
      this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
                color: AppTheme.foreground,
                fontWeight: FontWeight.w500,
              ),
        ),
      ),
      TextFormField(
        maxLines: maxLines,
        controller: controller,
        onTap: onTap,
        keyboardType: keyboardType,
        readOnly: readOnly,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: hintText,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    ]);
  }
}
