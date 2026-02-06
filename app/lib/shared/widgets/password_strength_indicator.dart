import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class PasswordStrengthIndicator extends StatelessWidget {
  final String password;
  final bool showRequirements;

  const PasswordStrengthIndicator({
    super.key,
    required this.password,
    this.showRequirements = true,
  });

  PasswordStrength _calculateStrength(String password) {
    if (password.isEmpty) {
      return PasswordStrength(
        score: 0,
        level: StrengthLevel.none,
        requirements: PasswordRequirements(),
      );
    }

    final requirements = PasswordRequirements(
      minLength: password.length >= 8,
      hasUpperCase: RegExp(r'[A-Z]').hasMatch(password),
      hasLowerCase: RegExp(r'[a-z]').hasMatch(password),
      hasNumbers: RegExp(r'\d').hasMatch(password),
      hasSpecialChar: RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password),
    );

    final score = [
      requirements.minLength,
      requirements.hasUpperCase,
      requirements.hasLowerCase,
      requirements.hasNumbers,
      requirements.hasSpecialChar,
    ].where((req) => req).length;

    StrengthLevel level;
    if (score == 0) {
      level = StrengthLevel.none;
    } else if (score <= 2) {
      level = StrengthLevel.weak;
    } else if (score <= 3) {
      level = StrengthLevel.medium;
    } else if (score <= 4) {
      level = StrengthLevel.strong;
    } else {
      level = StrengthLevel.veryStrong;
    }

    return PasswordStrength(
      score: score,
      level: level,
      requirements: requirements,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strength = _calculateStrength(password);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (password.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: AppTheme.muted,
                  ),
                  child: Row(
                    children: List.generate(5, (index) {
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(
                            right: index < 4 ? 2 : 0,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: index < strength.score
                                ? _getStrengthColor(strength.level)
                                : Colors.transparent,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _getStrengthText(strength.level),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _getStrengthColor(strength.level),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (showRequirements) ...[
            const SizedBox(height: 12),
            _buildRequirements(context, strength.requirements),
          ],
        ],
      ],
    );
  }

  Widget _buildRequirements(BuildContext context, PasswordRequirements requirements) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 12,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Password requirements:',
          style: textStyle?.copyWith(
            color: AppTheme.mutedForeground,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        _buildRequirement(
          context,
          'At least 8 characters',
          requirements.minLength,
          textStyle,
        ),
        _buildRequirement(
          context,
          'One uppercase letter',
          requirements.hasUpperCase,
          textStyle,
        ),
        _buildRequirement(
          context,
          'One lowercase letter',
          requirements.hasLowerCase,
          textStyle,
        ),
        _buildRequirement(
          context,
          'One number',
          requirements.hasNumbers,
          textStyle,
        ),
        _buildRequirement(
          context,
          'One special character',
          requirements.hasSpecialChar,
          textStyle,
        ),
      ],
    );
  }

  Widget _buildRequirement(
    BuildContext context,
    String text,
    bool isMet,
    TextStyle? textStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: isMet ? AppTheme.success : AppTheme.mutedForeground,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: textStyle?.copyWith(
              color: isMet ? AppTheme.success : AppTheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStrengthColor(StrengthLevel level) {
    switch (level) {
      case StrengthLevel.none:
        return AppTheme.mutedForeground;
      case StrengthLevel.weak:
        return AppTheme.destructive;
      case StrengthLevel.medium:
        return AppTheme.warning;
      case StrengthLevel.strong:
        return AppTheme.gold;
      case StrengthLevel.veryStrong:
        return AppTheme.success;
    }
  }

  String _getStrengthText(StrengthLevel level) {
    switch (level) {
      case StrengthLevel.none:
        return '';
      case StrengthLevel.weak:
        return 'Weak';
      case StrengthLevel.medium:
        return 'Medium';
      case StrengthLevel.strong:
        return 'Strong';
      case StrengthLevel.veryStrong:
        return 'Very Strong';
    }
  }
}

class PasswordStrength {
  final int score;
  final StrengthLevel level;
  final PasswordRequirements requirements;

  PasswordStrength({
    required this.score,
    required this.level,
    required this.requirements,
  });
}

class PasswordRequirements {
  final bool minLength;
  final bool hasUpperCase;
  final bool hasLowerCase;
  final bool hasNumbers;
  final bool hasSpecialChar;

  PasswordRequirements({
    this.minLength = false,
    this.hasUpperCase = false,
    this.hasLowerCase = false,
    this.hasNumbers = false,
    this.hasSpecialChar = false,
  });
}

enum StrengthLevel {
  none,
  weak,
  medium,
  strong,
  veryStrong,
}