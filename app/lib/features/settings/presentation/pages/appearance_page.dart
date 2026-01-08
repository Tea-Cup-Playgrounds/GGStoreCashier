import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/provider/theme_provider.dart';

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Appearance'),
      ),
      body: Column(
        children: [
          ListTile(
            title: const Text('Dark Mode'),
            subtitle: Text(isDark ? 'Enabled' : 'Disabled'),
            trailing: Switch.adaptive(
              value: isDark,
              inactiveThumbColor: Colors.grey.shade400,
              onChanged: (_) => ref.read(themeProvider.notifier).toggleTheme(),
            ),
          ),
        ],
      ),
    );
  }
}
