import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

/// A small dismissible dialog for non-fatal, recoverable errors.
///
/// Displays a [title], a human-readable [message], a "Tutup" dismiss button,
/// and an optional secondary action button when [onRetry] is provided.
class ErrorModal extends StatelessWidget {
  const ErrorModal({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Coba Lagi',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup'),
                ),
                if (onRetry != null) ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: onRetry,
                    child: Text(retryLabel),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows an [ErrorModal] using [showGeneralDialog] with a [FadeScaleTransition]
/// entrance/exit animation from the `animations` package.
///
/// The dialog is barrier-dismissible and does not cause navigation side effects
/// when dismissed — it simply pops itself.
Future<void> showErrorModal(
  BuildContext context, {
  required String title,
  required String message,
  VoidCallback? onRetry,
  String retryLabel = 'Coba Lagi',
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, anim1, anim2) => ErrorModal(
      title: title,
      message: message,
      onRetry: onRetry,
      retryLabel: retryLabel,
    ),
    transitionBuilder: (ctx, anim1, anim2, child) =>
        FadeScaleTransition(animation: anim1, child: child),
  );
}
