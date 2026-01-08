import 'package:flutter/material.dart';
import 'package:gg_store_cashier/features/devices/presentation/widgets/devices.dart';
import 'package:gg_store_cashier/features/devices/presentation/widgets/custom_title.dart';
import 'package:gg_store_cashier/shared/widgets/refresh_button.dart';

class PrinterDevicesPage extends StatefulWidget {
  const PrinterDevicesPage({super.key});

  @override
  State<PrinterDevicesPage> createState() => _PrinterDevicesPageState();
}

class _PrinterDevicesPageState extends State<PrinterDevicesPage>
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
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        // Judul dan Subtitle Kustom
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Printer',
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
                  title: 'Epson TM-T88VI',
                  type: 'Printer',
                  isConnected: true,
                  isPaired: true,
                  icon: Icons.print_outlined,
                  extraInfo: '14',
                  onPressed: () {
                    debugPrint("Disconnect Printer");
                  },
                ),
                const SizedBox(height: 20),
                Devices(
                  title: 'Epson TM-T88VI',
                  type: 'Printer',
                  isConnected: false,
                  isPaired: true,
                  icon: Icons.print_outlined,
                  onPressed: () {
                    debugPrint("Disconnect Printer");
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
                title: 'Epson TM-T88VI',
                type: 'Printer',
                icon: Icons.print_outlined,
                onPressed: () {
                  debugPrint("Disconnect Printer");
                },
              );
            },
          ),
        ]),
      ),
    );
  }
}
