import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Paper Size ────────────────────────────────────────────────────────────────

enum PaperWidth { mm58, mm80 }

class PaperSize {
  final String label;
  final String dimensions;
  final PaperWidth width;
  const PaperSize({required this.label, required this.dimensions, required this.width});
}

const _paperSizes = [
  PaperSize(label: '58mm · 57×30mm', dimensions: '57x30mm', width: PaperWidth.mm58),
  PaperSize(label: '58mm · 57×40mm', dimensions: '57x40mm', width: PaperWidth.mm58),
  PaperSize(label: '58mm · 58×30mm', dimensions: '58x30mm', width: PaperWidth.mm58),
  PaperSize(label: '80mm · 80×50mm', dimensions: '80x50mm', width: PaperWidth.mm80),
  PaperSize(label: '80mm · 80×80mm', dimensions: '80x80mm', width: PaperWidth.mm80),
];

// ── Receipt Section model ─────────────────────────────────────────────────────

enum SectionType { logo, header, contact, divider, items, totals, payment, footer, barcode }

class ReceiptSection {
  final SectionType type;
  bool visible;

  ReceiptSection({required this.type, this.visible = true});

  String get label {
    switch (type) {
      case SectionType.logo:    return 'Store Logo';
      case SectionType.header:  return 'Store Name & Branch';
      case SectionType.contact: return 'Address & Phone';
      case SectionType.divider: return 'Divider Line';
      case SectionType.items:   return 'Item List';
      case SectionType.totals:  return 'Subtotal / Tax / Total';
      case SectionType.payment: return 'Payment Method';
      case SectionType.footer:  return 'Footer Message';
      case SectionType.barcode: return 'Barcode / QR Code';
    }
  }

  IconData get icon {
    switch (type) {
      case SectionType.logo:    return Icons.image_outlined;
      case SectionType.header:  return Icons.store_outlined;
      case SectionType.contact: return Icons.location_on_outlined;
      case SectionType.divider: return Icons.horizontal_rule;
      case SectionType.items:   return Icons.list_alt_outlined;
      case SectionType.totals:  return Icons.calculate_outlined;
      case SectionType.payment: return Icons.payment_outlined;
      case SectionType.footer:  return Icons.notes_outlined;
      case SectionType.barcode: return Icons.qr_code_outlined;
    }
  }
}

// ── Main Page ─────────────────────────────────────────────────────────────────

class ReceiptEditorPage extends StatefulWidget {
  const ReceiptEditorPage({super.key});

  @override
  State<ReceiptEditorPage> createState() => _ReceiptEditorPageState();
}

class _ReceiptEditorPageState extends State<ReceiptEditorPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  static const _prefsKey = 'receipt_config';

  PaperSize _selectedSize = _paperSizes.first;

  final _storeNameCtrl   = TextEditingController(text: 'GG Store');
  final _branchCtrl      = TextEditingController(text: 'Downtown Branch');
  final _addressCtrl     = TextEditingController(text: 'Jl. Contoh No. 1, Jakarta');
  final _phoneCtrl       = TextEditingController(text: '+62 812-3456-7890');
  final _footerCtrl      = TextEditingController(text: 'Thank you for your purchase!');
  final _taxLabelCtrl    = TextEditingController(text: 'PPN');
  final _discountLabelCtrl = TextEditingController(text: 'Discount');
  final _voucherLabelCtrl  = TextEditingController(text: 'Voucher');

  double _taxRate = 11.0;
  bool _taxEnabled = true;
  bool _discountEnabled = true;
  bool _voucherEnabled = true;
  bool _showCashierName = true;
  bool _showTransactionId = true;
  bool _showDateTime = true;

  List<ReceiptSection> _sections = [
    ReceiptSection(type: SectionType.logo),
    ReceiptSection(type: SectionType.header),
    ReceiptSection(type: SectionType.contact),
    ReceiptSection(type: SectionType.divider),
    ReceiptSection(type: SectionType.items),
    ReceiptSection(type: SectionType.totals),
    ReceiptSection(type: SectionType.payment),
    ReceiptSection(type: SectionType.divider, visible: true),
    ReceiptSection(type: SectionType.barcode),
    ReceiptSection(type: SectionType.footer),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadConfig();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    for (final c in [_storeNameCtrl, _branchCtrl, _addressCtrl, _phoneCtrl,
        _footerCtrl, _taxLabelCtrl, _discountLabelCtrl, _voucherLabelCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _storeNameCtrl.text    = m['storeName']    ?? _storeNameCtrl.text;
        _branchCtrl.text       = m['branch']       ?? _branchCtrl.text;
        _addressCtrl.text      = m['address']      ?? _addressCtrl.text;
        _phoneCtrl.text        = m['phone']        ?? _phoneCtrl.text;
        _footerCtrl.text       = m['footer']       ?? _footerCtrl.text;
        _taxLabelCtrl.text     = m['taxLabel']     ?? _taxLabelCtrl.text;
        _discountLabelCtrl.text= m['discountLabel']?? _discountLabelCtrl.text;
        _voucherLabelCtrl.text = m['voucherLabel'] ?? _voucherLabelCtrl.text;
        _taxRate               = (m['taxRate']     ?? 11.0).toDouble();
        _taxEnabled            = m['taxEnabled']   ?? true;
        _discountEnabled       = m['discountEnabled'] ?? true;
        _voucherEnabled        = m['voucherEnabled']  ?? true;
        _showCashierName       = m['showCashierName'] ?? true;
        _showTransactionId     = m['showTransactionId'] ?? true;
        _showDateTime          = m['showDateTime'] ?? true;
        final sizeIdx          = m['paperSizeIndex'] ?? 0;
        _selectedSize          = _paperSizes[sizeIdx.clamp(0, _paperSizes.length - 1)];
        if (m['sections'] != null) {
          final sl = m['sections'] as List;
          _sections = sl.map((s) {
            final t = SectionType.values.firstWhere(
                (e) => e.name == s['type'], orElse: () => SectionType.divider);
            return ReceiptSection(type: t, visible: s['visible'] ?? true);
          }).toList();
        }
      });
    } catch (_) {}
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode({
      'storeName':       _storeNameCtrl.text,
      'branch':          _branchCtrl.text,
      'address':         _addressCtrl.text,
      'phone':           _phoneCtrl.text,
      'footer':          _footerCtrl.text,
      'taxLabel':        _taxLabelCtrl.text,
      'discountLabel':   _discountLabelCtrl.text,
      'voucherLabel':    _voucherLabelCtrl.text,
      'taxRate':         _taxRate,
      'taxEnabled':      _taxEnabled,
      'discountEnabled': _discountEnabled,
      'voucherEnabled':  _voucherEnabled,
      'showCashierName': _showCashierName,
      'showTransactionId': _showTransactionId,
      'showDateTime':    _showDateTime,
      'paperSizeIndex':  _paperSizes.indexOf(_selectedSize),
      'sections': _sections.map((s) => {'type': s.type.name, 'visible': s.visible}).toList(),
    }));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt settings saved')),
      );
    }
  }

  bool _sectionVisible(SectionType t) =>
      _sections.any((s) => s.type == t && s.visible);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: scheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Receipt Editor',
            style: Theme.of(context).textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w600)),
        backgroundColor: scheme.surface,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saveConfig,
            child: Text('Save',
                style: TextStyle(color: AppTheme.goldDark, fontWeight: FontWeight.w600)),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'Content'),
            Tab(text: 'Layout'),
            Tab(text: 'Preview'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _ContentTab(
            selectedSize: _selectedSize,
            onSizeChanged: (s) => setState(() => _selectedSize = s),
            storeNameCtrl: _storeNameCtrl,
            branchCtrl: _branchCtrl,
            addressCtrl: _addressCtrl,
            phoneCtrl: _phoneCtrl,
            footerCtrl: _footerCtrl,
            taxLabelCtrl: _taxLabelCtrl,
            discountLabelCtrl: _discountLabelCtrl,
            voucherLabelCtrl: _voucherLabelCtrl,
            taxRate: _taxRate,
            taxEnabled: _taxEnabled,
            discountEnabled: _discountEnabled,
            voucherEnabled: _voucherEnabled,
            showCashierName: _showCashierName,
            showTransactionId: _showTransactionId,
            showDateTime: _showDateTime,
            onTaxRateChanged: (v) => setState(() => _taxRate = v),
            onTaxEnabledChanged: (v) => setState(() => _taxEnabled = v),
            onDiscountEnabledChanged: (v) => setState(() => _discountEnabled = v),
            onVoucherEnabledChanged: (v) => setState(() => _voucherEnabled = v),
            onCashierNameChanged: (v) => setState(() => _showCashierName = v),
            onTransactionIdChanged: (v) => setState(() => _showTransactionId = v),
            onDateTimeChanged: (v) => setState(() => _showDateTime = v),
          ),
          _LayoutTab(
            sections: _sections,
            onReorder: (oldIdx, newIdx) {
              setState(() {
                if (newIdx > oldIdx) newIdx--;
                final item = _sections.removeAt(oldIdx);
                _sections.insert(newIdx, item);
              });
            },
            onToggle: (idx, val) => setState(() => _sections[idx].visible = val),
          ),
          _PreviewTab(
            paperSize: _selectedSize,
            storeName: _storeNameCtrl.text,
            branch: _branchCtrl.text,
            address: _sectionVisible(SectionType.contact) ? _addressCtrl.text : null,
            phone: _sectionVisible(SectionType.contact) ? _phoneCtrl.text : null,
            footer: _footerCtrl.text,
            taxLabel: _taxLabelCtrl.text,
            discountLabel: _discountLabelCtrl.text,
            voucherLabel: _voucherLabelCtrl.text,
            taxRate: _taxRate,
            taxEnabled: _taxEnabled,
            discountEnabled: _discountEnabled,
            voucherEnabled: _voucherEnabled,
            showLogo: _sectionVisible(SectionType.logo),
            showBarcode: _sectionVisible(SectionType.barcode),
            showCashierName: _showCashierName,
            showTransactionId: _showTransactionId,
            showDateTime: _showDateTime,
            sections: _sections,
          ),
        ],
      ),
    );
  }
}

// ── Content Tab ───────────────────────────────────────────────────────────────

class _ContentTab extends StatelessWidget {
  final PaperSize selectedSize;
  final ValueChanged<PaperSize> onSizeChanged;
  final TextEditingController storeNameCtrl, branchCtrl, addressCtrl,
      phoneCtrl, footerCtrl, taxLabelCtrl, discountLabelCtrl, voucherLabelCtrl;
  final double taxRate;
  final bool taxEnabled, discountEnabled, voucherEnabled;
  final bool showCashierName, showTransactionId, showDateTime;
  final ValueChanged<double> onTaxRateChanged;
  final ValueChanged<bool> onTaxEnabledChanged, onDiscountEnabledChanged,
      onVoucherEnabledChanged, onCashierNameChanged,
      onTransactionIdChanged, onDateTimeChanged;

  const _ContentTab({
    required this.selectedSize,
    required this.onSizeChanged,
    required this.storeNameCtrl,
    required this.branchCtrl,
    required this.addressCtrl,
    required this.phoneCtrl,
    required this.footerCtrl,
    required this.taxLabelCtrl,
    required this.discountLabelCtrl,
    required this.voucherLabelCtrl,
    required this.taxRate,
    required this.taxEnabled,
    required this.discountEnabled,
    required this.voucherEnabled,
    required this.showCashierName,
    required this.showTransactionId,
    required this.showDateTime,
    required this.onTaxRateChanged,
    required this.onTaxEnabledChanged,
    required this.onDiscountEnabledChanged,
    required this.onVoucherEnabledChanged,
    required this.onCashierNameChanged,
    required this.onTransactionIdChanged,
    required this.onDateTimeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Paper Size
          const _SecTitle('Paper Size'),
          const SizedBox(height: 8),
          _PaperSizeDropdown(selected: selectedSize, onChanged: onSizeChanged),
          const SizedBox(height: 24),

          // Store Info
          const _SecTitle('Store Info'),
          const SizedBox(height: 8),
          _RField(label: 'Store Name', ctrl: storeNameCtrl),
          const SizedBox(height: 8),
          _RField(label: 'Branch / Subheader', ctrl: branchCtrl),
          const SizedBox(height: 24),

          // Contact
          const _SecTitle('Contact Info'),
          const SizedBox(height: 8),
          _RField(label: 'Address', ctrl: addressCtrl, maxLines: 2),
          const SizedBox(height: 8),
          _RField(label: 'Phone', ctrl: phoneCtrl),
          const SizedBox(height: 24),

          // Tax
          const _SecTitle('Tax'),
          const SizedBox(height: 8),
          _ToggleTile(
            label: 'Enable Tax',
            icon: Icons.percent,
            value: taxEnabled,
            onChanged: onTaxEnabledChanged,
          ),
          if (taxEnabled) ...[
            const SizedBox(height: 8),
            _RField(label: 'Tax Label (e.g. PPN)', ctrl: taxLabelCtrl),
            const SizedBox(height: 12),
            _TaxRateSlider(value: taxRate, onChanged: onTaxRateChanged),
          ],
          const SizedBox(height: 24),

          // Discount & Voucher
          const _SecTitle('Discount & Voucher'),
          const SizedBox(height: 8),
          _ToggleTile(
            label: 'Show Discount Line',
            icon: Icons.discount_outlined,
            value: discountEnabled,
            onChanged: onDiscountEnabledChanged,
          ),
          if (discountEnabled) ...[
            const SizedBox(height: 8),
            _RField(label: 'Discount Label', ctrl: discountLabelCtrl),
          ],
          const SizedBox(height: 8),
          _ToggleTile(
            label: 'Show Voucher / Coupon Line',
            icon: Icons.local_offer_outlined,
            value: voucherEnabled,
            onChanged: onVoucherEnabledChanged,
          ),
          if (voucherEnabled) ...[
            const SizedBox(height: 8),
            _RField(label: 'Voucher Label', ctrl: voucherLabelCtrl),
          ],
          const SizedBox(height: 24),

          // Transaction Details
          const _SecTitle('Transaction Details'),
          const SizedBox(height: 8),
          _ToggleTile(
            label: 'Show Date & Time',
            icon: Icons.access_time_outlined,
            value: showDateTime,
            onChanged: onDateTimeChanged,
          ),
          const SizedBox(height: 8),
          _ToggleTile(
            label: 'Show Transaction ID',
            icon: Icons.tag_outlined,
            value: showTransactionId,
            onChanged: onTransactionIdChanged,
          ),
          const SizedBox(height: 8),
          _ToggleTile(
            label: 'Show Cashier Name',
            icon: Icons.person_outline,
            value: showCashierName,
            onChanged: onCashierNameChanged,
          ),
          const SizedBox(height: 24),

          // Footer
          const _SecTitle('Footer'),
          const SizedBox(height: 8),
          _RField(label: 'Footer Message', ctrl: footerCtrl, maxLines: 3),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Layout Tab (drag-and-drop) ────────────────────────────────────────────────

class _LayoutTab extends StatelessWidget {
  final List<ReceiptSection> sections;
  final void Function(int, int) onReorder;
  final void Function(int, bool) onToggle;

  const _LayoutTab({
    required this.sections,
    required this.onReorder,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Drag to reorder · Toggle to show/hide',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: sections.length,
            onReorder: onReorder,
            proxyDecorator: (child, index, animation) => Material(
              color: Colors.transparent,
              child: child,
            ),
            itemBuilder: (context, i) {
              final s = sections[i];
              return Container(
                key: ValueKey('${s.type.name}_$i'),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: scheme.secondary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: s.visible ? scheme.outline : scheme.outline.withOpacity(0.4),
                  ),
                ),
                child: ListTile(
                  leading: Icon(s.icon,
                      size: 20,
                      color: s.visible
                          ? scheme.onSurface.withOpacity(0.7)
                          : scheme.onSurface.withOpacity(0.3)),
                  title: Text(
                    s.label,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: s.visible
                              ? scheme.onSurface
                              : scheme.onSurface.withOpacity(0.4),
                        ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch.adaptive(
                        value: s.visible,
                        onChanged: (v) => onToggle(i, v),
                        activeColor: AppTheme.goldDark,
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.drag_handle,
                          color: scheme.onSurface.withOpacity(0.3), size: 20),
                    ],
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Preview Tab ───────────────────────────────────────────────────────────────

class _PreviewTab extends StatelessWidget {
  final PaperSize paperSize;
  final String storeName, branch, footer, taxLabel, discountLabel, voucherLabel;
  final String? address, phone;
  final double taxRate;
  final bool taxEnabled, discountEnabled, voucherEnabled;
  final bool showLogo, showBarcode, showCashierName, showTransactionId, showDateTime;
  final List<ReceiptSection> sections;

  const _PreviewTab({
    required this.paperSize,
    required this.storeName,
    required this.branch,
    this.address,
    this.phone,
    required this.footer,
    required this.taxLabel,
    required this.discountLabel,
    required this.voucherLabel,
    required this.taxRate,
    required this.taxEnabled,
    required this.discountEnabled,
    required this.voucherEnabled,
    required this.showLogo,
    required this.showBarcode,
    required this.showCashierName,
    required this.showTransactionId,
    required this.showDateTime,
    required this.sections,
  });

  bool _vis(SectionType t) => sections.any((s) => s.type == t && s.visible);

  @override
  Widget build(BuildContext context) {
    final isNarrow = paperSize.width == PaperWidth.mm58;
    final previewWidth = isNarrow ? 220.0 : 280.0;
    const subtotal = 35000.0;
    const discount = 5000.0;
    const voucher  = 2000.0;
    final taxAmt   = taxEnabled ? subtotal * (taxRate / 100) : 0.0;
    final discAmt  = discountEnabled ? discount : 0.0;
    final vouchAmt = voucherEnabled ? voucher : 0.0;
    final total    = subtotal + taxAmt - discAmt - vouchAmt;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Center(
        child: Container(
          width: previewWidth,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            children: [
              // Tape top
              Container(height: 6, color: const Color(0xFFEEEEEE)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.black, fontSize: 9, height: 1.5),
                  child: Column(
                    children: [
                      // Logo
                      if (_vis(SectionType.logo)) ...[
                        Image.asset('assets/images/GG_Logo.png', height: 48, fit: BoxFit.contain),
                        const SizedBox(height: 6),
                      ],
                      // Header
                      if (_vis(SectionType.header)) ...[
                        Text(storeName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
                            textAlign: TextAlign.center),
                        Text(branch,
                            style: const TextStyle(fontSize: 10, color: Colors.black54),
                            textAlign: TextAlign.center),
                      ],
                      // Contact
                      if (_vis(SectionType.contact)) ...[
                        const SizedBox(height: 4),
                        if (address != null)
                          Text(address!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 9, color: Colors.black54)),
                        if (phone != null)
                          Text(phone!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 9, color: Colors.black54)),
                      ],
                      // Transaction meta
                      if (showDateTime || showTransactionId || showCashierName) ...[
                        const _PDivider(),
                        if (showDateTime)
                          _PRow(left: 'Date', right: '08/04/2026 14:32'),
                        if (showTransactionId)
                          _PRow(left: 'TRX ID', right: '#TRX-00123'),
                        if (showCashierName)
                          _PRow(left: 'Cashier', right: 'Budi Santoso'),
                      ],
                      // Items
                      if (_vis(SectionType.items)) ...[
                        const _PDivider(),
                        _PRow(left: 'Kopi Susu x2', right: _fmt(20000)),
                        _PRow(left: 'Croissant x1', right: _fmt(15000)),
                        _PRow(left: 'Air Mineral x1', right: _fmt(5000)),
                      ],
                      // Totals
                      if (_vis(SectionType.totals)) ...[
                        const _PDivider(),
                        _PRow(left: 'Subtotal', right: _fmt(subtotal)),
                        if (taxEnabled)
                          _PRow(left: '$taxLabel (${taxRate.toStringAsFixed(0)}%)', right: _fmt(taxAmt)),
                        if (discountEnabled)
                          _PRow(left: discountLabel, right: '-${_fmt(discAmt)}'),
                        if (voucherEnabled)
                          _PRow(left: voucherLabel, right: '-${_fmt(vouchAmt)}'),
                        const _PDivider(),
                        _PRow(left: 'TOTAL', right: _fmt(total), bold: true),
                      ],
                      // Payment
                      if (_vis(SectionType.payment)) ...[
                        const SizedBox(height: 4),
                        _PRow(left: 'Payment', right: 'Cash'),
                        _PRow(left: 'Paid', right: _fmt(total + 5000)),
                        _PRow(left: 'Change', right: _fmt(5000)),
                      ],
                      // Barcode
                      if (_vis(SectionType.barcode)) ...[
                        const _PDivider(),
                        const SizedBox(height: 4),
                        Container(
                          height: 36,
                          width: double.infinity,
                          color: const Color(0xFFF0F0F0),
                          child: const Center(
                            child: Text('▌▌▌▌ ▌ ▌▌▌ ▌▌▌▌ ▌ ▌▌',
                                style: TextStyle(fontSize: 9, color: Colors.black38, letterSpacing: 1)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text('TRX-00123',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 8, color: Colors.black38)),
                        const SizedBox(height: 4),
                      ],
                      // Footer
                      if (_vis(SectionType.footer)) ...[
                        const _PDivider(),
                        Text(footer,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 9, color: Colors.black54)),
                      ],
                      const SizedBox(height: 4),
                      Text(paperSize.label,
                          style: const TextStyle(fontSize: 7, color: Colors.black26)),
                    ],
                  ),
                ),
              ),
              // Tape bottom (torn edge)
              ClipPath(
                clipper: _TornEdgeClipper(),
                child: Container(height: 14, color: const Color(0xFFEEEEEE)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return 'Rp $buf';
  }
}

class _TornEdgeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    double x = 0;
    const step = 8.0;
    bool up = true;
    while (x < size.width) {
      x += step;
      path.lineTo(x.clamp(0, size.width), up ? size.height * 0.4 : 0);
      up = !up;
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_) => false;
}

class _PDivider extends StatelessWidget {
  const _PDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 5),
      child: Divider(height: 1, color: Colors.black12),
    );
  }
}

class _PRow extends StatelessWidget {
  final String left, right;
  final bool bold;
  const _PRow({required this.left, required this.right, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 9,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: Colors.black87,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(left, style: style), Text(right, style: style)],
      ),
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _SecTitle extends StatelessWidget {
  final String title;
  const _SecTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: Theme.of(context).textTheme.titleSmall!.copyWith(letterSpacing: 0.8));
  }
}

class _PaperSizeDropdown extends StatelessWidget {
  final PaperSize selected;
  final ValueChanged<PaperSize> onChanged;
  const _PaperSizeDropdown({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PaperSize>(
          value: selected,
          isExpanded: true,
          dropdownColor: scheme.secondary,
          items: _paperSizes.map((s) => DropdownMenuItem(
            value: s,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: s.width == PaperWidth.mm58
                        ? AppTheme.goldDark.withOpacity(0.15)
                        : Colors.blue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    s.width == PaperWidth.mm58 ? '58mm' : '80mm',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: s.width == PaperWidth.mm58 ? AppTheme.goldDark : Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(s.dimensions, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          )).toList(),
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ),
    );
  }
}

class _RField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final int maxLines;
  const _RField({required this.label, required this.ctrl, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: scheme.secondary,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outline)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.goldDark, width: 1.5)),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleTile({required this.label, required this.icon, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: ListTile(
        leading: Icon(icon, color: scheme.onSurface.withOpacity(0.6), size: 20),
        title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        trailing: Switch.adaptive(value: value, onChanged: onChanged, activeColor: AppTheme.goldDark),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        dense: true,
      ),
    );
  }
}

class _TaxRateSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _TaxRateSlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tax Rate', style: Theme.of(context).textTheme.bodyMedium),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.goldDark.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${value.toStringAsFixed(1)}%',
                  style: const TextStyle(
                      color: AppTheme.goldDark, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: 0,
            max: 25,
            divisions: 50,
            activeColor: AppTheme.goldDark,
            inactiveColor: AppTheme.goldDark.withOpacity(0.2),
            onChanged: onChanged,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0%', style: Theme.of(context).textTheme.bodySmall),
              Text('25%', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
