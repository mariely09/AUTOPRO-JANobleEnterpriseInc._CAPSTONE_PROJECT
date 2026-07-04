import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'barcode_scanner_screen.dart';
import 'admin_inventory_hub.dart';
import 'admin_vehicle_maintenance.dart';

/// Reusable bottom navigation bar for the Admin Dashboard.
/// Handles tab switching and the center scanner button.
class AdminBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _red = Color(0xFFE8001C);

  static const _navItems = [
    (icon: Icons.dashboard_outlined, label: 'Dashboard'),
    (icon: Icons.inventory_2_outlined, label: 'Inventory'),
    (icon: Icons.directions_car_outlined, label: 'Vehicles'),
    (icon: Icons.more_horiz, label: 'More'),
  ];

  const AdminBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x18000000), blurRadius: 12, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 2 left + center placeholder + 2 right
              Row(children: [
                _navBtn(context, 0),
                _navBtn(context, 1),
                const Expanded(child: SizedBox()), // center placeholder
                _navBtn(context, 2),
                _navBtn(context, 3),
              ]),
              // Center floating scanner button
              Positioned(
                top: -20, left: 0, right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => _showScanModal(context),
                    child: Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: _red,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: _red.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navBtn(BuildContext context, int i) {
    final active = currentIndex == i;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(i),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_navItems[i].icon, color: active ? _red : const Color(0xFF718096), size: 22),
          const SizedBox(height: 2),
          Text(_navItems[i].label, style: TextStyle(
            fontSize: 9,
            color: active ? _red : const Color(0xFF718096),
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          )),
        ]),
      ),
    );
  }

  // ── Barcode / QR scanner modal ──
  void _showScanModal(BuildContext context) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (result == null) return;
    if (!context.mounted) return;

    final trimmed = result.trim();
    final query   = trimmed.toLowerCase();

    // Step 1: Resolve via item_master
    Map<String, dynamic>? masterItem;
    String resolvedNum  = '';
    String resolvedName = '';

    try {
      QuerySnapshot snap = await FirebaseFirestore.instance
          .collection('item_master').where('barcode', isEqualTo: trimmed).limit(1).get();
      if (snap.docs.isEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('item_master').where('qr', isEqualTo: trimmed).limit(1).get();
      }
      if (snap.docs.isEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('item_master').where('num', isEqualTo: trimmed.toUpperCase()).limit(1).get();
      }
      if (snap.docs.isEmpty) {
        final all = await FirebaseFirestore.instance.collection('item_master').get();
        final match = all.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return (data['name'] as String? ?? '').toLowerCase().contains(query) ||
                 (data['barcode'] as String? ?? '') == trimmed ||
                 (data['qr']      as String? ?? '') == trimmed;
        }).toList();
        if (match.isNotEmpty) {
          snap = await FirebaseFirestore.instance
              .collection('item_master').where(FieldPath.documentId, isEqualTo: match.first.id).limit(1).get();
        }
      }
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data() as Map<String, dynamic>;
        resolvedNum  = (d['num']  as String? ?? '').toLowerCase();
        resolvedName = (d['name'] as String? ?? '').toLowerCase();
        masterItem   = {'id': snap.docs.first.id, ...d};
      }
    } catch (e) {
      debugPrint('item_master lookup error: $e');
    }

    if (!context.mounted) return;

    // Step 2: Check stock_inventory
    Map<String, dynamic>? stockItem;
    try {
      if (masterItem != null) {
        final snap = await FirebaseFirestore.instance
            .collection('stock_inventory')
            .where('num', isEqualTo: masterItem['num'] as String? ?? '')
            .limit(1).get();
        if (snap.docs.isNotEmpty) {
          final d = snap.docs.first.data() as Map<String, dynamic>;
          final stock = (d['stock'] as num?)?.toInt() ?? 0;
          final min   = (d['min']   as num?)?.toInt() ?? 0;
          final max   = (d['max']   as num?)?.toInt() ?? 0;
          stockItem = {'id': snap.docs.first.id, ...d, 'stock': stock, 'min': min, 'max': max,
            'status': stock > min ? (stock > max ? 'Over' : 'OK') : 'Low'};
        }
      }
    } catch (e) {
      debugPrint('stock lookup error: $e');
    }

    // Step 3: Find matching pending delivery
    Map<String, dynamic>? foundDelivery;
    try {
      final deliveriesSnap = await FirebaseFirestore.instance
          .collection('deliveries').where('status', isEqualTo: 'Pending').get();
      for (final doc in deliveriesSnap.docs) {
        final d = {...doc.data() as Map<String, dynamic>, 'id': doc.id};
        final items = (d['items'] as List? ?? []);
        final match = items.any((i) {
          final num  = (i['itemNum']  as String? ?? '').toLowerCase();
          final name = (i['itemName'] as String? ?? '').toLowerCase();
          return (resolvedNum.isNotEmpty  && num.contains(resolvedNum))  ||
                 (resolvedName.isNotEmpty && name.contains(resolvedName)) ||
                 num.contains(query) || name.contains(query);
        });
        if (match) { foundDelivery = d; break; }
      }
    } catch (e) {
      debugPrint('delivery lookup error: $e');
    }

    if (!context.mounted) return;
    _showScanResultModal(context, trimmed, masterItem, stockItem, foundDelivery);
  }

  void _showScanResultModal(
    BuildContext context,
    String rawValue,
    Map<String, dynamic>? masterItem,
    Map<String, dynamic>? stockItem,
    Map<String, dynamic>? delivery,
  ) {
    final itemName  = masterItem?['name'] as String? ?? rawValue;
    final itemNum   = masterItem?['num']  as String? ?? '—';
    final itemGroup = masterItem?['group'] as String? ?? '';
    final itemUom   = masterItem?['uom']  as String? ?? '';
    final itemCost  = masterItem?['cost'] as String? ?? '';
    final itemType  = masterItem?['type'] as String? ?? '';
    final isMaterial = itemType == 'Material' || masterItem == null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE8001C), Color(0xFFa50014)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(itemName,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  if (itemNum != '—' || itemGroup.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text([itemNum, if (itemGroup.isNotEmpty) itemGroup].join(' · '),
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ])),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.close, color: Colors.white, size: 16)),
                ),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Item chips
                if (masterItem != null &&
                    (itemUom.isNotEmpty || itemCost.isNotEmpty || itemType.isNotEmpty)) ...[
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (itemUom.isNotEmpty)
                      _infoBadge(Icons.straighten_outlined,   itemUom,  const Color(0xFF003087)),
                    if (itemCost.isNotEmpty)
                      _infoBadge(Icons.attach_money,          itemCost, const Color(0xFF38a169)),
                    if (itemType.isNotEmpty)
                      _infoBadge(Icons.category_outlined,     itemType, const Color(0xFFd69e2e)),
                  ]),
                  const SizedBox(height: 20),
                ],

                // Item not found
                if (masterItem == null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFD54F), width: 1.5)),
                    child: Row(children: [
                      const Icon(Icons.search_off_outlined, size: 18, color: Color(0xFFd69e2e)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        'Scanned value "$rawValue" was not found in the item master.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)))),
                    ]),
                  ),
                ] else ...[
                  const Text('What would you like to do?',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c))),
                  const SizedBox(height: 12),

                  // Option 1: View / Receive Stock
                  if (isMaterial && stockItem != null) ...[
                    _actionTile(
                      context: context,
                      icon: Icons.inventory_2_outlined,
                      iconColor: const Color(0xFF003087),
                      iconBg: const Color(0xFFEBF8FF),
                      title: 'View Stock',
                      subtitle: 'Current: ${stockItem['stock']} ${stockItem['uom'] ?? ''} · ${stockItem['status']}',
                      onTap: () {
                        Navigator.pop(context);
                        _showStockDetailModal(context, stockItem);
                      },
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Option 2: Receive from delivery
                  if (delivery != null) ...[
                    _actionTile(
                      context: context,
                      icon: Icons.download_outlined,
                      iconColor: const Color(0xFF38a169),
                      iconBg: const Color(0xFFF0FFF4),
                      title: 'Receive Items',
                      subtitle: 'From delivery by ${delivery['supplier']}',
                      badge: 'Pending',
                      badgeColor: const Color(0xFF718096),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AdminInventoryHub(
                            initialTab: 2,
                            deliveryToReceive: delivery)));
                      },
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Option 3: Use in Maintenance
                  _actionTile(
                    context: context,
                    icon: Icons.build_outlined,
                    iconColor: const Color(0xFFd69e2e),
                    iconBg: const Color(0xFFFFFBEB),
                    title: 'Use in Maintenance',
                    subtitle: 'Add to a vehicle maintenance record',
                    onTap: () {
                      Navigator.pop(context);
                      final matData = {
                        'name': masterItem!['name'] as String? ?? '',
                        'num':  masterItem!['num']  as String? ?? '',
                        'uom':  masterItem!['uom']  as String? ?? '',
                        'cost': masterItem!['cost'] as String? ?? '0',
                      };
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => AdminVehicleMaintenance(materialData: matData)));
                    },
                  ),
                  const SizedBox(height: 10),

                  // Option 4: Add to Stock (if not yet in stock_inventory)
                  if (isMaterial && stockItem == null)
                    _actionTile(
                      context: context,
                      icon: Icons.add_box_outlined,
                      iconColor: _red,
                      iconBg: const Color(0xFFFFF5F5),
                      title: 'Add to Stock Inventory',
                      subtitle: 'Set min/max levels and initial quantity',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const AdminInventoryHub()));
                      },
                    ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _infoBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _actionTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    String? badge,
    Color? badgeColor,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: disabled ? const Color(0xFFF7F8FA) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFe2e8f0)),
          boxShadow: disabled ? [] : [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: disabled ? const Color(0xFFa0aec0) : const Color(0xFF1a202c))),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(
              fontSize: 11,
              color: disabled ? const Color(0xFFcbd5e0) : const Color(0xFF718096))),
          ])),
          if (badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (badgeColor ?? const Color(0xFF718096)).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20)),
              child: Text(badge, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: badgeColor ?? const Color(0xFF718096))),
            ),
          ] else if (!disabled)
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFa0aec0)),
        ]),
      ),
    );
  }

  void _showStockDetailModal(BuildContext context, Map<String, dynamic> item) {
    final status    = item['status'] as String? ?? 'OK';
    final isLow     = status == 'Low';
    final isOver    = status == 'Over';
    final stock     = (item['stock'] as num?)?.toInt() ?? 0;
    final min       = (item['min']   as num?)?.toInt() ?? 0;
    final max       = (item['max']   as num?)?.toInt() ?? 0;
    final progress  = max > 0 ? (stock / max).clamp(0.0, 1.0) : 0.0;
    final barColor  = isLow ? Colors.orange : isOver ? Colors.purple : Colors.green;
    final statusLabel = isLow ? 'Low Stock' : isOver ? 'Over Max' : 'In Stock';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.6, maxChildSize: 0.88,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                  color: _red,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item['name'] as String? ?? '—',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(item['group'] as String? ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Stock level bar card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isLow ? Colors.orange.shade50 : const Color(0xFFF0FFF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isLow ? Colors.orange.shade200 : const Color(0xFF9AE6B4))),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('$stock ${item['uom'] ?? ''}',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: barColor)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: barColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                        child: Text(statusLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: barColor))),
                    ]),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: const Color(0xFFe2e8f0),
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        minHeight: 8)),
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Min: $min', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                      Text('$stock / $max',
                        style: TextStyle(fontSize: 11, color: barColor, fontWeight: FontWeight.w600)),
                      Text('Max: $max', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),
                _detailRowInline('Item Number',    item['num']     as String? ?? '—'),
                _detailRowInline('Commodity Group', item['group']  as String? ?? '—'),
                _detailRowInline('UOM',             item['uom']    as String? ?? '—'),
                _detailRowInline('Reorder Qty',    '${(item['reorder'] as num?)?.toInt() ?? 0} ${item['uom'] ?? ''}'),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _detailRowInline(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 140, child: Text(label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
      Expanded(child: Text(value.isEmpty ? '—' : value,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
    ]),
  );
}

// ── Scan: Add to Stock ──────────────────────────────────────────────────────
class _ScanAddStockWidget extends StatefulWidget {
  final Map<String, String> itemData;
  final VoidCallback onDone;
  const _ScanAddStockWidget({required this.itemData, required this.onDone});

  @override
  State<_ScanAddStockWidget> createState() => _ScanAddStockWidgetState();
}

class _ScanAddStockWidgetState extends State<_ScanAddStockWidget> {
  static const _red = Color(0xFFE8001C);
  final _stockCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final _reorderCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _stockCtrl.dispose(); _minCtrl.dispose(); _maxCtrl.dispose(); _reorderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uom = widget.itemData['uom'] ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFbee3f8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.add_box_outlined, color: _red, size: 16),
          SizedBox(width: 6),
          Text('Stock Level Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _red)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _stockCtrl, keyboardType: TextInputType.number, autofocus: true,
          decoration: InputDecoration(labelText: 'Current Quantity *', border: const OutlineInputBorder(),
            filled: true, fillColor: Colors.white, suffixText: uom),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            controller: _minCtrl, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Min Level *', border: const OutlineInputBorder(),
              filled: true, fillColor: Colors.white, suffixText: uom),
          )),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: _maxCtrl, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Max Level *', border: const OutlineInputBorder(),
              filled: true, fillColor: Colors.white, suffixText: uom),
          )),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _reorderCtrl, keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Reorder Quantity', border: const OutlineInputBorder(),
            filled: true, fillColor: Colors.white, suffixText: uom),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : () async {
              final stock = int.tryParse(_stockCtrl.text.trim()) ?? 0;
              final min   = int.tryParse(_minCtrl.text.trim())   ?? 0;
              final max   = int.tryParse(_maxCtrl.text.trim())   ?? 0;
              final reorder = int.tryParse(_reorderCtrl.text.trim()) ?? 0;
              if (_stockCtrl.text.isEmpty || _minCtrl.text.isEmpty || _maxCtrl.text.isEmpty) return;
              setState(() => _loading = true);
              try {
                final existing = await FirebaseFirestore.instance
                    .collection('stock_inventory')
                    .where('num', isEqualTo: widget.itemData['num'])
                    .limit(1).get();
                if (existing.docs.isNotEmpty) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Already in stock inventory.'), backgroundColor: Colors.orange));
                  setState(() => _loading = false);
                  return;
                }
                await FirebaseFirestore.instance.collection('stock_inventory').add({
                  'num': widget.itemData['num'], 'name': widget.itemData['name'],
                  'group': widget.itemData['group'], 'uom': widget.itemData['uom'],
                  'stock': stock, 'min': min, 'max': max, 'reorder': reorder,
                  'status': stock > min ? 'OK' : 'Low',
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                // No transaction logged for initial stock add
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added to stock inventory.'), backgroundColor: Colors.green));
                  widget.onDone();
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                setState(() => _loading = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.save_outlined, size: 16), SizedBox(width: 6), Text('Save to Stock'),
                  ]),
          ),
        ),
      ]),
    );
  }
}

// ── Scan: Receive Stock ─────────────────────────────────────────────────────
class _ScanReceiveWidget extends StatefulWidget {
  final String stockId;
  final Map<String, dynamic> stockData;
  final String uom;
  final VoidCallback onDone;
  const _ScanReceiveWidget({required this.stockId, required this.stockData, required this.uom, required this.onDone});

  @override
  State<_ScanReceiveWidget> createState() => _ScanReceiveWidgetState();
}

class _ScanReceiveWidgetState extends State<_ScanReceiveWidget> {
  static const _blue = Color(0xFF003087);
  final _qtyCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { _qtyCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final currentStock = (widget.stockData['stock'] as num?)?.toInt() ?? 0;
    final min = (widget.stockData['min'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFebf8ff),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF90cdf4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.download_outlined, color: _blue, size: 16),
          SizedBox(width: 6),
          Text('Receive Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _blue)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(
            controller: _qtyCtrl, keyboardType: TextInputType.number, autofocus: true,
            decoration: InputDecoration(labelText: 'Quantity to receive *', border: const OutlineInputBorder(),
              filled: true, fillColor: Colors.white, suffixText: widget.uom),
          )),
          const SizedBox(width: 10),
          SizedBox(height: 56, child: ElevatedButton(
            onPressed: _loading ? null : () async {
              final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
              if (qty <= 0) return;
              setState(() => _loading = true);
              try {
                final newStock = currentStock + qty;
                await FirebaseFirestore.instance.collection('stock_inventory').doc(widget.stockId).update({
                  'stock': newStock, 'status': newStock > min ? 'OK' : 'Low',
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                final byName = (userDoc.data()?['name'] as String?) ?? 'Admin';
                final now = DateTime.now();
                const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';
                await FirebaseFirestore.instance.collection('transactions').add({
                  'item': widget.stockData['name'] ?? '', 'desc': 'Stock received',
                  'type': 'IN', 'qty': '+$qty', 'date': dateStr, 'by': byName,
                  'stockId': widget.stockId, 'createdAt': FieldValue.serverTimestamp(),
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('+$qty ${widget.uom} received. New stock: $newStock'),
                    backgroundColor: Colors.green));
                  widget.onDone();
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                setState(() => _loading = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('✅ Confirm'),
          )),
        ]),
      ]),
    );
  }
}
