import 'package:flutter/material.dart';

enum ButtonVariant { primary, secondary, outline, ghost }

enum ButtonSize { small, medium, large, extraLarge }

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final ButtonSize size;
  final IconData? icon;
  final bool isLoading;
  final bool fullWidth;

  const CustomButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: _getHeight(),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: _getButtonStyle(context, colorScheme),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getLoadingColor(colorScheme),
                  ),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: _getIconSize()),
                    const SizedBox(width: 8),
                  ],
                  Text(text),
                ],
              ),
      ),
    );
  }

  // =========================
  // SIZE
  // =========================

  double _getHeight() => switch (size) {
        ButtonSize.small => 36,
        ButtonSize.medium => 44,
        ButtonSize.large => 52,
        ButtonSize.extraLarge => 60,
      };

  double _getIconSize() => switch (size) {
        ButtonSize.small => 16,
        ButtonSize.medium => 18,
        ButtonSize.large => 20,
        ButtonSize.extraLarge => 22,
      };

  EdgeInsets _getPadding() => switch (size) {
        ButtonSize.small =>
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ButtonSize.medium =>
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ButtonSize.large =>
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ButtonSize.extraLarge =>
          const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      };

  TextStyle _getTextStyle() {
    final fontSize = switch (size) {
      ButtonSize.small => 12.0,
      ButtonSize.medium => 14.0,
      ButtonSize.large => 16.0,
      ButtonSize.extraLarge => 18.0,
    };

    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
    );
  }

  // =========================
  // STYLE
  // =========================

  ButtonStyle _getButtonStyle(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final baseStyle = Theme.of(context).elevatedButtonTheme.style?.copyWith(
              padding: WidgetStateProperty.all(_getPadding()),
              textStyle: WidgetStateProperty.all(_getTextStyle()),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              elevation: WidgetStateProperty.all(0),
            ) ??
        ElevatedButton.styleFrom(
          elevation: 0,
          padding: _getPadding(),
          textStyle: _getTextStyle(),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        );

    BorderSide border(Color color) => BorderSide(color: color, width: 1);

    switch (variant) {
      case ButtonVariant.primary:
        return baseStyle.copyWith(
          backgroundColor: WidgetStateProperty.all(colorScheme.primary),
          foregroundColor: WidgetStateProperty.all(colorScheme.onPrimary),
          side: WidgetStateProperty.all(
            border(colorScheme.primary),
          ),
        );

      case ButtonVariant.secondary:
        return baseStyle.copyWith(
          backgroundColor: WidgetStateProperty.all(colorScheme.secondary),
          foregroundColor: WidgetStateProperty.all(colorScheme.onSecondary),
          side: WidgetStateProperty.all(
            border(colorScheme.secondary),
          ),
        );

      case ButtonVariant.outline:
        return baseStyle.copyWith(
          backgroundColor: WidgetStateProperty.all(Colors.transparent),
          foregroundColor: WidgetStateProperty.all(colorScheme.onSurface),
          side: WidgetStateProperty.all(
            border(colorScheme.outlineVariant),
          ),
        );

      case ButtonVariant.ghost:
        return baseStyle.copyWith(
          backgroundColor: WidgetStateProperty.all(Colors.transparent),
          foregroundColor: WidgetStateProperty.all(colorScheme.primary),
          side: WidgetStateProperty.all(
            border(colorScheme.primary.withOpacity(0.4)),
          ),
        );
    }
  }

  // =========================
  // LOADING COLOR
  // =========================

  Color _getLoadingColor(ColorScheme colorScheme) => switch (variant) {
        ButtonVariant.primary => colorScheme.onPrimary,
        ButtonVariant.secondary => colorScheme.onSecondary,
        ButtonVariant.outline => colorScheme.onSurface,
        ButtonVariant.ghost => colorScheme.primary,
      };
}
