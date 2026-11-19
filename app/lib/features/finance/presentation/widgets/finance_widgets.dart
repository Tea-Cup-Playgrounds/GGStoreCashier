import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';

// Shared pieces of the Keuangan (finance / accounting) screens.

/// Every location the API lists for the user (branches and the warehouse).
final financeLocationsProvider = FutureProvider<List<Location>>((ref) => CatalogService.getLocations());

/// Locations where the user holds any of [permissions]; null = every location (head office too).
Set<int>? scopeFor(UserAccess access, List<String> permissions) {
  final ids = <int>{};
  for (final p in permissions) {
    if (!access.can(p)) continue;
    final scope = access.locationsFor(p);
    if (scope == null) return null;
    ids.addAll(scope);
  }
  return ids;
}

const _monthNames = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
const _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String monthLabel(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';
String monthLabelOf(int year, int month) => '${_monthNames[month - 1]} $year';

/// 'YYYY-MM-DD' → '14 Nov 2026'.
String dayLabel(String date) {
  final d = DateTime.tryParse(date);
  return d == null ? date : '${d.day} ${_shortMonths[d.month - 1]} ${d.year}';
}

/// 'YYYY-MM' → 'November 2026'.
String yearMonthLabel(String ym) {
  final parts = ym.split('-');
  return parts.length == 2 ? monthLabelOf(int.parse(parts[0]), int.parse(parts[1])) : ym;
}

/// First and last day of [month]; the current month ends today.
(String, String) monthRange(DateTime month) {
  final now = DateTime.now();
  final first = DateTime(month.year, month.month, 1);
  final last = DateTime(month.year, month.month + 1, 0);
  return (ymd(first), ymd(last.isAfter(now) ? now : last));
}

String rp(num value) => CurrencyFormatter.formatToRupiah(value);

/// Chips for picking a location. With [allLabel] the first chip is "every location" (value null).
class FinanceLocationChips extends ConsumerWidget {
  final Set<int>? scope;
  final int? value;
  final String? allLabel;
  final ValueChanged<int?> onChanged;

  const FinanceLocationChips({super.key, required this.scope, required this.value, required this.onChanged, this.allLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final all = ref.watch(financeLocationsProvider).valueOrNull ?? const <Location>[];
    final locations = scope == null ? all : all.where((l) => scope!.contains(l.id)).toList();
    final options = <(int?, String, IconData)>[
      if (allLabel != null) (null, allLabel!, Icons.apartment_outlined),
      for (final l in locations) (l.id, l.code ?? l.name, l.isWarehouse ? Icons.warehouse_outlined : Icons.storefront_outlined),
    ];
    if (options.length <= 1 && allLabel == null && locations.length == 1) {
      // A single branch: show it, nothing to choose.
      return Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          avatar: Icon(options.first.$3, size: 16, color: AppTheme.gold),
          label: Text(locations.first.label),
          side: const BorderSide(color: AppTheme.gold),
        ),
      );
    }
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (id, label, icon) = options[i];
          final selected = id == value;
          return ChoiceChip(
            avatar: Icon(icon, size: 16, color: selected ? AppTheme.gold : cs.onSurfaceVariant),
            label: Text(label),
            selected: selected,
            showCheckmark: false,
            selectedColor: AppTheme.gold.withValues(alpha: 0.15),
            side: BorderSide(color: selected ? AppTheme.gold : cs.outlineVariant),
            labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? AppTheme.gold : cs.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
            onSelected: (_) => onChanged(id),
          );
        },
      ),
    );
  }
}

/// Dropdown for the location a new document belongs to. Users with every location may pick
/// head office ("Pusat", value null).
class FinanceLocationField extends ConsumerWidget {
  final Set<int>? scope;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String label;

  const FinanceLocationField({super.key, required this.scope, required this.value, required this.onChanged, this.label = 'Lokasi'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(financeLocationsProvider).valueOrNull ?? const <Location>[];
    final locations = scope == null ? all : all.where((l) => scope!.contains(l.id)).toList();
    return DropdownButtonFormField<int?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.place_outlined), border: const OutlineInputBorder()),
      items: [
        if (scope == null) const DropdownMenuItem<int?>(value: null, child: Text('Pusat (kantor pusat, tanpa lokasi)')),
        for (final l in locations) DropdownMenuItem<int?>(value: l.id, child: Text(l.label)),
      ],
      validator: (v) => scope != null && v == null ? 'Pilih lokasi' : null,
      onChanged: onChanged,
    );
  }
}

/// "‹ November 2026 ›"; the next arrow stops at the current month.
class MonthStepper extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  const MonthStepper({super.key, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final atCurrent = month.year == now.year && month.month == now.month;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Bulan sebelumnya',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        ),
        Text(monthLabel(month), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        IconButton(
          tooltip: 'Bulan berikutnya',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: atCurrent ? null : () => onChanged(DateTime(month.year, month.month + 1)),
        ),
      ],
    );
  }
}

/// Label on the left, amount on the right.
class MoneyRow extends StatelessWidget {
  final String label;
  final num value;
  final bool bold;
  final Color? color;
  final String? sub;

  const MoneyRow(this.label, this.value, {super.key, this.bold = false, this.color, this.sub});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: style),
            if (sub != null) Text(sub!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 12),
        Text(rp(value), style: style),
      ]),
    );
  }
}

/// Loading / error / content in one place, with a retry button on errors.
class AsyncBody extends StatelessWidget {
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final Widget Function() builder;

  const AsyncBody({super.key, required this.loading, required this.error, required this.onRetry, required this.builder});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator(color: AppTheme.gold));
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 40, color: AppTheme.destructive),
            const SizedBox(height: 8),
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
          ]),
        ),
      );
    }
    return builder();
  }
}

/// Asks for a reason (voids). Returns null when cancelled.
Future<String?> askReason(BuildContext context, {required String title, required String message, String confirm = 'Batalkan'}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Alasan *', border: OutlineInputBorder()),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kembali')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.destructive),
          onPressed: () {
            final reason = controller.text.trim();
            if (reason.isNotEmpty) Navigator.pop(ctx, reason);
          },
          child: Text(confirm),
        ),
      ],
    ),
  );
}

/// Yes / no confirmation.
Future<bool> confirmAction(BuildContext context, {required String title, required String message, required String confirm}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.gold, foregroundColor: Colors.black), onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
      ],
    ),
  );
  return ok == true;
}

/// Date button that opens a picker; no future dates.
class DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const DateField({super.key, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(context: context, initialDate: value.isAfter(now) ? now : value, firstDate: DateTime(2020), lastDate: now);
        if (picked != null) onChanged(picked);
      },
      icon: const Icon(Icons.event_outlined),
      label: Text('$label: ${dayLabel(ymd(value))}'),
    );
  }
}
