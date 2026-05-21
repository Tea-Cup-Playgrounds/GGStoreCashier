import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TextInput extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final int maxLines;
  final bool readOnly;
  final String? hintText;
  final String? Function(String?)? validator;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final void Function(String)? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  const TextInput({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.hintText,
    this.onTap,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.readOnly = false,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.onChanged,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2.0, bottom: 4.0),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w500,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextFormField(
          maxLines: maxLines,
          controller: controller,
          onTap: onTap,
          onChanged: onChanged,
          keyboardType: keyboardType,
          readOnly: readOnly,
          obscureText: obscureText,
          validator: validator,
          inputFormatters: inputFormatters,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          // Scroll horizontally when text overflows (single line fields)
          scrollPhysics: maxLines == 1 ? const BouncingScrollPhysics() : null,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            errorStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ),
      ],
    );
  }
}
