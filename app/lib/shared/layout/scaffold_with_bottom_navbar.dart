import 'package:flutter/material.dart';
import 'package:gg_store_cashier/shared/widgets/bottom_navigation.dart';
import 'package:go_router/go_router.dart';

class ScaffoldWithBottomNavbar extends StatelessWidget {
  const ScaffoldWithBottomNavbar(this.navigationShell, {super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigation(navigationShell),
    );
  }
}
