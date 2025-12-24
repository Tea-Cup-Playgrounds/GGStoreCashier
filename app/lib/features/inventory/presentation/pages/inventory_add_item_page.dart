import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';

class InventoryAddItemPage extends StatefulWidget {
  const InventoryAddItemPage({super.key});

  @override
  State<InventoryAddItemPage> createState() => _InventoryAddItemState(); 
 }

class _InventoryAddItemState extends State<InventoryAddItemPage>{
  final _formKey = GlobalKey<FormState>();
 @override
   Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
            onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back)),
        title: const Text(
          "Tambah Product",
          style: TextStyle(
              fontWeight: FontWeight.w600, color: AppTheme.foreground),
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: const SingleChildScrollView(
        child: Center(
          child: Text("Walawe kok merah"),
        ),
      ),
    );
  }

}