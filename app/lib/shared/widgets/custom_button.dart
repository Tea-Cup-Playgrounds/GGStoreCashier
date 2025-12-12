import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

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
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: _getHeight(),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: _getButtonStyle(),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getLoadingColor(),
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

  double _getHeight() {
    switch (size) {
      case ButtonSize.small:
        return 36;
      case ButtonSize.medium:
        return 44;
      case ButtonSize.large:
        return 52;
      case ButtonSize.extraLarge:
        return 60;
    }
  }

  double _getIconSize() {
    switch (size) {
      case ButtonSize.small:
        return 16;
      case ButtonSize.medium:
        return 18;
      case ButtonSize.large:
        return 20;
      case ButtonSize.extraLarge:
        return 22;
    }
  }

  Color _getLoadingColor() {
    switch (variant) {
      case ButtonVariant.primary:
        return AppTheme.background;
      case ButtonVariant.secondary:
        return AppTheme.foreground;
      case ButtonVariant.outline:
        return AppTheme.foreground;
      case ButtonVariant.ghost:
        return AppTheme.gold;
    }
  }

  ButtonStyle _getButtonStyle() {
    final baseStyle = ElevatedButton.styleFrom(
      elevation: 0,
      padding: _getPadding(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: _getTextStyle(),
    );

    switch (variant) {
      case ButtonVariant.primary:
        return baseStyle.copyWith(
          backgroundColor: WidgetStateProperty.all(AppTheme.gold),
          foregroundColor: WidgetStateProperty.all(AppTheme.background),
        );
      case ButtonVariant.secondary:
        return baseStyle.copyWith(
          backgroundColor: WidgetStateProperty.all(AppTheme.secondary),
          foregroundColor: WidgetStateProperty.all(AppTheme.secondaryForeground),
        );
      case ButtonVariant.outline:
        return baseStyle.copyWith(
          backgroundColor: WidgetStateProperty.all(Colors.transparent),
          foregroundColor: WidgetStateProperty.all(AppTheme.foreground),
          side: WidgetStateProperty.all(
            const BorderSide(color: AppTheme.border),
          ),
        );
      case ButtonVariant.ghost:
        return baseStyle.copyWith(
          backgroundColor: WidgetStateProperty.all(Colors.transparent),
          foregroundColor: WidgetStateProperty.all(AppTheme.gold),
        );
    }
  }

  EdgeInsets _getPadding() {
    switch (size) {
      case ButtonSize.small:
        return const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
      case ButtonSize.medium:
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
      case ButtonSize.large:
        return const EdgeInsets.symmetric(horizontal:20, vertical: 12);
      case ButtonSize.extraLarge:
        return const EdgeInsets.symmetric(horizontal: 24, vertical: 16);
    }
  }

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
}