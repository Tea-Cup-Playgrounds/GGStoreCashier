import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../core/helper/currency_formatter.dart';
import '../../../../core/models/catalog.dart';
import '../../../../core/provider/access_provider.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/connectivity_monitor.dart';
import '../../../../core/services/offline_queue.dart';
import '../../../../core/services/pending_operations_queue.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/theme/app_theme.dart';

final _time = DateFormat('dd-MM-yyyy HH:mm');

/// Everything saved on this device that the server doesn't have yet: sales made offline (or whose
/// response was lost) and other queued changes. Waiting items are sent automatically; items the
/// server refused stay here, with its reason, until someone retries or removes them.
class SyncQueuePage extends ConsumerWidget {
  const SyncQueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectivityProvider).valueOrNull != ConnectivityStatus.offline;
    final access = ref.watch(currentAccessProvider);
    final locations = ref.watch(stockLocationsProvider).valueOrNull ?? const <Location>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Sinkronisasi')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          OfflineQueue.box.listenable(),
          PendingOperationsQueue.box.listenable(),
          SyncService.isRunning,
          SyncService.needsLogin,
        ]),
        builder: (context, _) {
          final sales = OfflineQueue.getAll();
          final ops = PendingOperationsQueue.getAll();
          final waiting = sales.where((e) => !e.isFailed).length + ops.where((o) => o.status != 'failed').length;
          final failed = sales.where((e) => e.isFailed).length + ops.where((o) => o.status == 'failed').length;

          return RefreshIndicator(
            onRefresh: SyncService.syncAll,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusCard(online: online, waiting: waiting, failed: failed),
                const SizedBox(height: 16),
                if (sales.isEmpty && ops.isEmpty)
                  const _EmptyState()
                else ...[
                  if (sales.isNotEmpty) ...[
                    const _SectionTitle('Penjualan'),
                    for (final entry in sales.reversed)
                      _SaleCard(
                        entry: entry,
                        location: locations.where((l) => l.id == entry.locationId).firstOrNull,
                        canDelete: entry.locationId != null && access.can('sales.void', entry.locationId),
                      ),
                  ],
                  if (ops.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const _SectionTitle('Perubahan data lain'),
                    for (final op in ops.reversed) _OperationCard(op: op),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusCard extends ConsumerWidget {
  final bool online;
  final int waiting;
  final int failed;

  const _StatusCard({required this.online, required this.waiting, required this.failed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = SyncService.isRunning.value;
    final needsLogin = SyncService.needsLogin.value;
    final theme = Theme.of(context);

    final (IconData icon, Color color, String title, String detail) = switch (true) {
      _ when needsLogin => (
          Icons.lock_outline,
          AppTheme.warning,
          'Login ulang diperlukan',
          'Sesi login sudah berakhir. Transaksi tetap aman di perangkat ini dan dikirim setelah login ulang.',
        ),
      _ when !online => (
          Icons.cloud_off_outlined,
          AppTheme.warning,
          'Offline',
          'Transaksi dikirim otomatis saat koneksi kembali.',
        ),
      _ when failed > 0 => (
          Icons.error_outline,
          AppTheme.destructive,
          '$failed ditolak server',
          'Lihat alasannya di bawah. Perbaiki di server lalu coba lagi, atau salin datanya untuk dicatat manual.',
        ),
      _ when waiting > 0 => (
          Icons.cloud_upload_outlined,
          AppTheme.gold,
          '$waiting menunggu dikirim',
          'Dikirim otomatis setiap menit selama ada koneksi.',
        ),
      _ => (
          Icons.cloud_done_outlined,
          AppTheme.success,
          'Semua terkirim',
          'Tidak ada data yang tertinggal di perangkat ini.',
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 6),
            Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (waiting > 0 || failed > 0) ...[
              const SizedBox(height: 4),
              Text('$waiting menunggu · $failed ditolak', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            if (needsLogin)
              FilledButton.icon(
                onPressed: () async {
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) context.go(AppRouter.login);
                },
                icon: const Icon(Icons.login),
                label: const Text('Login ulang'),
              )
            else
              FilledButton.icon(
                onPressed: running || !online || waiting == 0 ? null : SyncService.syncAll,
                icon: running
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: Text(running ? 'Mengirim...' : 'Kirim sekarang'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final OfflineTransactionEntry entry;
  final Location? location;
  final bool canDelete;

  const _SaleCard({required this.entry, required this.location, required this.canDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = entry.chargedTotal;
    final details = [
      _time.format(entry.createdAt),
      location?.code ?? (entry.locationId != null ? 'Lokasi ${entry.locationId}' : null),
      '${entry.itemCount} barang',
      entry.cashierName,
    ].whereType<String>().join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  total != null ? CurrencyFormatter.formatToRupiah(total) : 'Penjualan',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _StatusChip(failed: entry.isFailed),
            ]),
            const SizedBox(height: 4),
            Text(details, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (entry.lastError != null) ...[
              const SizedBox(height: 8),
              _ErrorBox(
                message: entry.lastError!,
                failed: entry.isFailed,
                when: entry.lastAttemptAt,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (entry.isFailed)
                  TextButton.icon(
                    onPressed: () async {
                      await OfflineQueue.retry(entry.uuid);
                      SyncService.syncAll();
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Coba lagi'),
                  ),
                TextButton.icon(
                  onPressed: () => _copy(context, entry.payload),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Salin data'),
                ),
                if (entry.isFailed && canDelete)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
                    onPressed: () => _confirmDelete(context),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Hapus'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus transaksi?'),
        content: const Text(
          'Penjualan ini belum ada di server. Setelah dihapus dari perangkat, datanya hilang dan tidak bisa '
          'dikembalikan. Salin datanya dulu dan catat penjualan ini secara manual bila perlu.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) await OfflineQueue.remove(entry.uuid);
  }
}

class _OperationCard extends StatelessWidget {
  final PendingOperation op;

  const _OperationCard({required this.op});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = op.status == 'failed';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(op.description, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
              _StatusChip(failed: failed),
            ]),
            const SizedBox(height: 4),
            Text(_time.format(op.createdAt), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (failed)
              Wrap(spacing: 8, children: [
                TextButton.icon(
                  onPressed: () async {
                    await PendingOperationsQueue.retry(op.id);
                    SyncService.syncAll();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Coba lagi'),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
                  onPressed: () => PendingOperationsQueue.remove(op.id),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Buang perubahan'),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool failed;

  const _StatusChip({required this.failed});

  @override
  Widget build(BuildContext context) {
    final color = failed ? AppTheme.destructive : AppTheme.gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        failed ? 'Ditolak' : 'Menunggu',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final bool failed;
  final DateTime? when;

  const _ErrorBox({required this.message, required this.failed, this.when});

  @override
  Widget build(BuildContext context) {
    final color = failed ? AppTheme.destructive : AppTheme.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        when != null ? '$message\n(${_time.format(when!)})' : message,
        style: TextStyle(color: color, fontSize: 13),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(children: [
        Icon(Icons.cloud_done_outlined, size: 56, color: muted.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Text('Semua data sudah terkirim', style: TextStyle(color: muted)),
      ]),
    );
  }
}

Future<void> _copy(BuildContext context, Map<dynamic, dynamic> payload) async {
  await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data transaksi disalin')));
  }
}
