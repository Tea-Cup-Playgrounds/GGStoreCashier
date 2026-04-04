import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:gg_store_cashier/core/services/error_handler.dart';

String _assetFor(AppErrorType type) {
  switch (type) {
    case AppErrorType.offline:
      return 'assets/lottie/offline.json';
    case AppErrorType.serverError:
      return 'assets/lottie/server_error.json';
    case AppErrorType.maintenance:
      return 'assets/lottie/maintenance.json';
    case AppErrorType.timeout:
      return 'assets/lottie/timeout.json';
    case AppErrorType.authError:
      return 'assets/lottie/auth_error.json';
    case AppErrorType.unknown:
      return 'assets/lottie/unknown_error.json';
  }
}

class ErrorPage extends StatelessWidget {
  final AppError error;
  final VoidCallback? onRetry;
  final VoidCallback? onGoHome;

  const ErrorPage({
    super.key,
    required this.error,
    this.onRetry,
    this.onGoHome,
  });

  @override
  Widget build(BuildContext context) {
    final fullMessage = ErrorHandler.messageFor(error.type);
    final title = fullMessage.contains(' — ')
        ? fullMessage.split(' — ').first
        : fullMessage;

    final buttonLabel = onRetry != null ? 'Coba Lagi' : 'Kembali ke Beranda';
    final buttonCallback = onRetry ?? onGoHome;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = constraints.maxWidth > constraints.maxHeight;
            final lottieHeight = isLandscape ? 160.0 : 240.0;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Lottie.asset(
                      _assetFor(error.type),
                      height: lottieHeight,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      error.userMessage,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                      textAlign: TextAlign.center,
                    ),
                    if (buttonCallback != null) ...[
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: buttonCallback,
                        child: Text(buttonLabel),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
