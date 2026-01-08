import 'package:flutter/material.dart';
import 'package:gg_store_cashier/features/devices/presentation/widgets/devices.dart';
import 'package:gg_store_cashier/features/devices/presentation/widgets/custom_title.dart';
import 'package:gg_store_cashier/shared/widgets/refresh_button.dart';

class ScannerDevicesPage extends StatefulWidget {
  const ScannerDevicesPage({super.key});

  @override
  State<ScannerDevicesPage> createState() => _ScannerDevicesPageState();
}

class _ScannerDevicesPageState extends State<ScannerDevicesPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _refreshController;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _refreshController.stop();
    _refreshController.reset();
    _refreshController.dispose();
    super.dispose();
  }

  void _refreshDevices() async {
    _refreshController.repeat();

    // TODO: scan bluetooth
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    _refreshController.stop();
    _refreshController.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        // Judul dan Subtitle Kustom
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scanner',
              style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CustomTitle(title: "Perangkat yang disandingkan"),
          const SizedBox(
            height: 20.0,
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 1,
            separatorBuilder: (_, __) => const SizedBox(height: 20),
            itemBuilder: (context, index) {
              return Column(children: [
                Devices(
                  title: 'Scanner SMKJFKFo',
                  type: 'Scanner',
                  isConnected: true,
                  isPaired: true,
                  icon: Icons.qr_code_2_outlined,
                  extraInfo: '14',
                  onPressed: () {
                    debugPrint("Disconnect Scanner");
                  },
                ),
                const SizedBox(height: 20),
                Devices(
                  title: 'Scanner SMKJFKFo',
                  type: 'Scanner',
                  isConnected: false,
                  isPaired: true,
                  icon: Icons.qr_code_2_outlined,
                  onPressed: () {
                    debugPrint("Disconnect Scanner");
                  },
                ),
              ]);
            },
          ),
          Row(children: [
            const CustomTitle(title: "Perangkat yang tersedia"),
            const Spacer(),
            RefreshButton(
              onRefresh: _refreshDevices,
              refreshController: _refreshController,
            ),
          ]),
          const SizedBox(
            height: 20.0,
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 1,
            separatorBuilder: (_, __) => const SizedBox(height: 20),
            itemBuilder: (context, index) {
              return Devices(
                isPaired: false,
                title: 'Scanner SMKJFKFo',
                type: 'Scanner',
                icon: Icons.qr_code_2_outlined,
                onPressed: () {
                  debugPrint("Disconnect Scanner");
                },
              );
            },
          ),
        ]),
      ),
    );
  }
}
