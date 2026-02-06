import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/connectivity_test.dart';
import '../theme/app_theme.dart';

class ApiConfigDialog extends StatefulWidget {
  const ApiConfigDialog({super.key});

  @override
  State<ApiConfigDialog> createState() => _ApiConfigDialogState();
}

class _ApiConfigDialogState extends State<ApiConfigDialog> {
  String _selectedEnvironment = ApiConfig.currentEnvironment;
  bool _isTestingConnection = false;
  String? _connectionResult;

  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
      _connectionResult = null;
    });

    final isConnected = await ConnectivityTest.testConnection();
    
    setState(() {
      _isTestingConnection = false;
      _connectionResult = isConnected 
          ? 'Connection successful!' 
          : 'Connection failed. Check console for details.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text(
        'API Configuration',
        style: TextStyle(color: AppTheme.foreground),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current API URL:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.muted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                ApiConfig.apiUrl,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.gold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Available Environments:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...ApiConfig.environments.entries.map((entry) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: entry.key == _selectedEnvironment 
                      ? AppTheme.gold.withOpacity(0.1)
                      : AppTheme.muted,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: entry.key == _selectedEnvironment 
                        ? AppTheme.gold
                        : AppTheme.border,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            entry.value,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.mutedForeground,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (entry.key == _selectedEnvironment)
                      const Icon(
                        Icons.check_circle,
                        color: AppTheme.gold,
                        size: 20,
                      ),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isTestingConnection ? null : _testConnection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: AppTheme.background,
                ),
                child: _isTestingConnection
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.background,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('Testing...'),
                        ],
                      )
                    : const Text('Test Connection'),
              ),
            ),
            if (_connectionResult != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _connectionResult!.contains('successful')
                      ? AppTheme.success.withOpacity(0.1)
                      : AppTheme.destructive.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _connectionResult!.contains('successful')
                        ? AppTheme.success
                        : AppTheme.destructive,
                  ),
                ),
                child: Text(
                  _connectionResult!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _connectionResult!.contains('successful')
                        ? AppTheme.success
                        : AppTheme.destructive,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Close',
            style: TextStyle(color: AppTheme.mutedForeground),
          ),
        ),
      ],
    );
  }
}