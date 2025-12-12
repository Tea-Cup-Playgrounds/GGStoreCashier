import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/bottom_navigation.dart';

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  // Widget Pembantu untuk Judul Bagian
  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge!.copyWith(
              color: AppTheme.foreground,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Bluetooth Devices'),
        backgroundColor: AppTheme.background,
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Devices
            Text(
              '1 of 2 devices connected',
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: AppTheme.mutedForeground,
                  ),
            ),
            const SizedBox(height: 16.0),

            // 1. HEADER STATUS BLUETOOTH
            const _StatusHeader(
              title: 'Bluetooth',
              subtitle: 'Enabled',
              icon: Icons.bluetooth_audio,
              isConnected: true,
            ),
            const SizedBox(height: 16.0),

            // 2. BAGIAN BARCODE SCANNERS
            _buildSectionTitle(context, 'Barcode Scanners'),
            _DeviceTile(
              title: 'Zebra DS9308',
              type: 'Scanner',
              isConnected: true,
              icon: Icons.qr_code_scanner,
              onPrimaryAction: () {
                // Aksi: Disconnect
              },
            ),
            const SizedBox(height: 16.0),

            // 3. BAGIAN RECEIPT PRINTERS
            _buildSectionTitle(context, 'Receipt Printers'),
            _DeviceTile(
              title: 'Epson TM-T88VI',
              type: 'Printer • Covilo 10 meters',
              isConnected: false,
              icon: Icons.print_outlined,
              extraInfo: '14',
              onPrimaryAction: () {
                // Aksi: Connect
              },
            ),
            const SizedBox(height: 32.0),

            // 4. BAGIAN PAIRING TIPS
            _buildSectionTitle(context, 'Pairing Tips'),
            const _PairingTips(),

            const SizedBox(height: 32.0),
          ],
        ),
      ),
      // BOTTOM NAVIGATION BAR
      bottomNavigationBar: const BottomNavigation(),
    );
  }
}

// =========================================================================
// WIDGET PEMBANTU
// =========================================================================

// Widget Kustom untuk Header Status Bluetooth (dengan Tombol Scan interaktif)
class _StatusHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isConnected;

  const _StatusHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        // Gradient mewah
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.card,
            Color(0xFF1F1F1F),
          ],
        ),
      ),
      child: Row(
        children: [
          // Icon Status
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.gold,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppTheme.background, size: 24),
          ),
          const SizedBox(width: 16),
          // Judul dan Status
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Row(
                children: [
                  const Icon(Icons.wifi, size: 14, color: AppTheme.success),
                  const SizedBox(width: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: AppTheme.success,
                        ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          // Tombol Scan (Interaktif)
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.refresh),
            label: const Text('Scan'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.gold,
              side: const BorderSide(color: AppTheme.gold),
              // Efek hover/klik
              overlayColor: AppTheme.gold.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}

// Widget Kustom untuk Tile Perangkat (Dengan Tata Letak Column dan Tombol Interaktif)
class _DeviceTile extends StatelessWidget {
  final String title;
  final String type;
  final IconData icon;
  final bool isConnected;
  final String? extraInfo;
  final VoidCallback onPrimaryAction;

  const _DeviceTile({
    required this.title,
    required this.type,
    required this.icon,
    required this.isConnected,
    this.extraInfo,
    required this.onPrimaryAction,
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon Perangkat (kotak hijau/emas)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  // Jika connected, gunakan warna Success (Hijau)
                  color: isConnected ? AppTheme.success : AppTheme.gold,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(icon, color: AppTheme.background, size: 24),
                ),
              ),
              const SizedBox(width: 16),
              // Detail Perangkat (Menggunakan Column untuk Detail)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Judul Perangkat
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        // Checkmark jika connected, atau Extra Info jika disconnected
                        if (isConnected)
                          const Icon(Icons.check_circle,
                              color: AppTheme.success, size: 20),
                        if (!isConnected && extraInfo != null)
                          Text(extraInfo!,
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Tipe dan Status Koneksi DIBUAT DALAM COLUMN
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Baris Tipe
                        Text(
                          type,
                          style:
                              Theme.of(context).textTheme.bodyMedium!.copyWith(
                                    color: AppTheme.mutedForeground,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        // Baris Status
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
                            ),
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
          // Tombol Aksi (Connect/Disconnect) - Interaktif
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPrimaryAction,
              style: ElevatedButton.styleFrom(
                // Warna Connect: AppTheme.goldDark
                // Warna Disconnect: AppTheme.secondary
                backgroundColor:
                    isConnected ? AppTheme.secondary : AppTheme.goldDark,
                foregroundColor:
                    isConnected ? AppTheme.foreground : AppTheme.background,
                // Efek hover/klik
                overlayColor: isConnected
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

// Widget untuk menampilkan Tips
class _PairingTips extends StatelessWidget {
  const _PairingTips();

  @override
  Widget build(BuildContext context) {
    const List<String> tips = [
      'Make sure your device is in pairing mode',
      'Keep devices within 10 meters range',
      'Check device battery before connecting',
    ];

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: tips.map((tip) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6.0),
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppTheme.gold,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tip,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: AppTheme.mutedForeground,
                        ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
