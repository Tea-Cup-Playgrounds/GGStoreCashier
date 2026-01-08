import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';

class Devices extends StatelessWidget {
  final String title;
  final String type;
  final IconData icon;
  final bool isConnected;
  final String? extraInfo;
  final VoidCallback onPressed;
  final bool isPaired;

  const Devices({
    super.key,
    required this.title,
    required this.type,
    required this.icon,
    this.isPaired = false,
    this.isConnected = false,
    required this.onPressed,
    this.extraInfo,
  });

  @override
  Widget build(BuildContext context) {
    final Color statusColor =
        isConnected ? AppTheme.success : AppTheme.mutedForeground;
    final String statusText = isConnected ? 'Connected' : 'Disconnected';
    final String actionText = isConnected ? 'Disconnect' : 'Connect';

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isPaired ? AppTheme.success : AppTheme.gold,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(icon, color: Theme.of(context).colorScheme.surface, size: 24),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (isConnected)
                          const Icon(Icons.check_circle,
                              color: AppTheme.success, size: 20),
                        if (!isConnected && extraInfo != null)
                          Text(extraInfo!,
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type,
                          style:
                              Theme.of(context).textTheme.bodyMedium
                        ),
                        const SizedBox(height: 4),
                        if (isPaired)
                          Row(
                            children: [
                              Icon(Icons.link, size: 14, color: statusColor),
                              const SizedBox(width: 4),
                              Text(
                                statusText,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium!
                                    .copyWith(
                                      color: statusColor,
                                    ),
                              )
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isPaired ? Theme.of(context).colorScheme.outlineVariant : AppTheme.goldDark,
                foregroundColor:
                    isPaired ? AppTheme.foreground : AppTheme.background,
                overlayColor: isPaired
                    ? AppTheme.foreground.withOpacity(0.1)
                    : AppTheme.background.withOpacity(0.2),
                elevation: 0,
              ),
              child: Text(actionText),
            ),
          ),
        ],
      ),
    );
  }
}
