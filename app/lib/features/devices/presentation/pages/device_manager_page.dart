import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/features/devices/data/device_service.dart';
import 'package:gg_store_cashier/features/devices/presentation/widgets/custom_title.dart';
import 'package:gg_store_cashier/shared/widgets/refresh_button.dart';

enum _DeviceTab { printer, scanner }

class DeviceManagerPage extends StatefulWidget {
  const DeviceManagerPage({super.key});

  @override
  State<DeviceManagerPage> createState() => _DeviceManagerPageState();
}

class _DeviceManagerPageState extends State<DeviceManagerPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _refreshController;
  _DeviceTab _activeTab = _DeviceTab.printer;
  bool _isScanning = false;
  bool _btUnavailable = false;

  List<PairedDevice> _pairedDevices = [];
  final List<DiscoveredDevice> _discovered = [];
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _loadPaired();
    _watchAdapter();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _loadPaired() async {
    final list = await DeviceService.loadPaired();
    if (mounted) setState(() => _pairedDevices = list);
  }

  void _watchAdapter() {
    _adapterSub = DeviceService.adapterState.listen((state) {
      if (mounted) {
        setState(() => _btUnavailable = state != BluetoothAdapterState.on);
      }
    });
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _btUnavailable = false;
      _discovered.clear();
    });
    _refreshController.repeat();

    final granted = await DeviceService.requestBluetoothPermissions();
    if (!granted) {
      if (mounted) {
        setState(() => _isScanning = false);
        _refreshController.stop();
        _refreshController.reset();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth permission denied')),
        );
      }
      return;
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _btUnavailable = true;
        });
        _refreshController.stop();
        _refreshController.reset();
      }
      return;
    }

    final seen = <String>{};
    _scanSub = DeviceService.scanBluetooth(
      duration: const Duration(seconds: 6),
    ).listen(
      (device) {
        if (!seen.contains(device.id)) {
          seen.add(device.id);
          if (mounted) setState(() => _discovered.add(device));
        }
      },
      onDone: _onScanDone,
      onError: (_) => _onScanDone(),
    );
  }

  void _onScanDone() {
    if (!mounted) return;
    _refreshController.stop();
    _refreshController.reset();
    setState(() => _isScanning = false);
  }

  Future<void> _pairDevice(DiscoveredDevice d) async {
    final category = await _showCategoryDialog();
    if (category == null) return;

    final paired = PairedDevice(
      id: d.id,
      name: d.name,
      connectionType: d.connectionType,
      category: category,
      isConnected: false,
    );
    await DeviceService.addPaired(paired);
    await _loadPaired();
    if (mounted) {
      setState(() => _discovered.removeWhere((x) => x.id == d.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${d.name} berhasil dipasangkan')),
      );
    }
  }

  Future<void> _unpairDevice(PairedDevice d) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Perangkat'),
        content: Text('Hapus "${d.name}" dari perangkat yang dipasangkan?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: AppTheme.destructive)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DeviceService.removePaired(d.id);
      await _loadPaired();
    }
  }

  Future<DeviceCategory?> _showCategoryDialog() {
    return showDialog<DeviceCategory>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Device Type'),
        content: const Text('What type of device is this?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, DeviceCategory.printer),
            child: const Text('Printer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, DeviceCategory.scanner),
            child: const Text('Scanner'),
          ),
        ],
      ),
    );
  }

  List<PairedDevice> get _filteredPaired => _pairedDevices
      .where((d) => _activeTab == _DeviceTab.printer
          ? d.category == DeviceCategory.printer
          : d.category == DeviceCategory.scanner)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Device Manager',
          style: Theme.of(context).textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: _TabSelector(
              active: _activeTab,
              onChanged: (tab) => setState(() => _activeTab = tab),
            ),
          ),
          if (_btUnavailable)
            _BtWarningBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Paired ──────────────────────────────────────────────
                  const CustomTitle(title: 'Paired Devices'),
                  const SizedBox(height: 12),
                  if (_filteredPaired.isEmpty)
                    _EmptyPaired(tab: _activeTab)
                  else
                    ..._filteredPaired.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PairedDeviceCard(
                            device: d,
                            onRemove: () => _unpairDevice(d),
                          ),
                        )),
                  const SizedBox(height: 8),

                  // ── Available ───────────────────────────────────────────
                  Row(
                    children: [
                      const CustomTitle(title: 'Available Devices'),
                      const Spacer(),
                      RefreshButton(
                        onRefresh: _startScan,
                        refreshController: _refreshController,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isScanning)
                    const _SkeletonList()
                  else if (_discovered.isEmpty)
                    _EmptyScanPrompt(onScan: _startScan)
                  else
                    ..._discovered.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _DiscoveredDeviceCard(
                            device: d,
                            onPair: () => _pairDevice(d),
                          ),
                        )),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── BT Warning ────────────────────────────────────────────────────────────────

class _BtWarningBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_disabled, color: AppTheme.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bluetooth is off. Enable it to scan for devices.',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(color: AppTheme.warning),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab Selector ──────────────────────────────────────────────────────────────

class _TabSelector extends StatelessWidget {
  final _DeviceTab active;
  final ValueChanged<_DeviceTab> onChanged;
  const _TabSelector({required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.secondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          _TabItem(label: 'Printer', icon: Icons.print_outlined,
              isActive: active == _DeviceTab.printer, onTap: () => onChanged(_DeviceTab.printer)),
          _TabItem(label: 'Scanner', icon: Icons.qr_code_scanner,
              isActive: active == _DeviceTab.scanner, onTap: () => onChanged(_DeviceTab.scanner)),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  const _TabItem({required this.label, required this.icon, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.goldDark : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18,
                  color: isActive ? AppTheme.background : scheme.onSurface.withOpacity(0.6)),
              const SizedBox(width: 6),
              Text(label,
                  style: Theme.of(context).textTheme.labelLarge!.copyWith(
                        color: isActive ? AppTheme.background : scheme.onSurface.withOpacity(0.6),
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Paired Device Card ────────────────────────────────────────────────────────

class _PairedDeviceCard extends StatelessWidget {
  final PairedDevice device;
  final VoidCallback onRemove;
  const _PairedDeviceCard({required this.device, required this.onRemove});

  IconData get _icon => device.category == DeviceCategory.printer
      ? Icons.print_outlined
      : Icons.qr_code_2_outlined;

  IconData get _connIcon {
    switch (device.connectionType) {
      case DeviceConnectionType.wifi: return Icons.wifi;
      case DeviceConnectionType.usb: return Icons.usb;
      case DeviceConnectionType.bluetooth: return Icons.bluetooth;
    }
  }

  String get _connLabel {
    switch (device.connectionType) {
      case DeviceConnectionType.wifi: return 'Wi-Fi';
      case DeviceConnectionType.usb: return 'USB';
      case DeviceConnectionType.bluetooth: return 'Bluetooth';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_icon, color: AppTheme.success, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(_connIcon, size: 12, color: scheme.onSurface.withOpacity(0.5)),
                    const SizedBox(width: 4),
                    Text(_connLabel,
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 8),
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: device.isConnected ? AppTheme.success : AppTheme.mutedForeground,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(device.isConnected ? 'Connected' : 'Disconnected',
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              color: device.isConnected ? AppTheme.success : AppTheme.mutedForeground,
                            )),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.link_off, size: 20),
            color: AppTheme.destructive,
            onPressed: onRemove,
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

// ── Discovered Device Card ────────────────────────────────────────────────────

class _DiscoveredDeviceCard extends StatelessWidget {
  final DiscoveredDevice device;
  final VoidCallback onPair;
  const _DiscoveredDeviceCard({required this.device, required this.onPair});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.goldDark.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bluetooth, color: AppTheme.goldDark, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('Bluetooth',
                        style: Theme.of(context).textTheme.bodySmall),
                    if (device.rssi != null) ...[
                      const SizedBox(width: 8),
                      Text('${device.rssi} dBm',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onPair,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.goldDark,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: const Text('Pair'),
          ),
        ],
      ),
    );
  }
}

// ── Skeleton Loading ──────────────────────────────────────────────────────────

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (_) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: _SkeletonCard(),
      )),
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.secondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: scheme.onSurface.withOpacity(_anim.value * 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 13, width: 130,
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withOpacity(_anim.value * 0.15),
                        borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 8),
                  Container(height: 10, width: 80,
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withOpacity(_anim.value * 0.1),
                        borderRadius: BorderRadius.circular(4))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty States ──────────────────────────────────────────────────────────────

class _EmptyPaired extends StatelessWidget {
  final _DeviceTab tab;
  const _EmptyPaired({required this.tab});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'No paired ${tab == _DeviceTab.printer ? "printers" : "scanners"} yet.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _EmptyScanPrompt extends StatelessWidget {
  final VoidCallback onScan;
  const _EmptyScanPrompt({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(Icons.bluetooth_searching, size: 48,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text('Tap refresh to scan for nearby Bluetooth devices',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
          ],
        ),
      ),
    );
  }
}
