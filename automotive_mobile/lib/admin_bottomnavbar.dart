import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'barcode_scanner_screen.dart';
import 'admin_inventory_hub.dart';
import 'admin_vehicle_maintenance.dart';
import 'admin_receiving.dart';

/// Reusable bottom navigation bar for the Admin Dashboard.
/// Handles tab switching and the center scanner button.
class AdminBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AdminBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<AdminBottomNavBar> createState() => _AdminBottomNavBarState();
}

class _AdminBottomNavBarState extends State<AdminBottomNavBar> {
  static const _red = Color(0xFFE8001C);

  static const _navItems = [
    (icon: Icons.dashboard_outlined, label: 'Dashboard'),
    (icon: Icons.inventory_2_outlined, label: 'Inventory'),
    (icon: Icons.directions_car_outlined, label: 'Vehicles'),
    (icon: Icons.more_horiz, label: 'More'),
  ];

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
                    onTap: _showScanModal,
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
    final active = widget.currentIndex == i;
    return Expanded(
      child: InkWell(
        onTap: () => widget.onTap(i),
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

  // ── Barcode / QR scanner modal — mirrors admin_inventory_stock add flow ──
  void _showScanModal() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (result == null || !mounted) return;

    final trimmed = result.trim();
    final query   = trimmed.toLowerCase();
    debugPrint('🔍 Scanned: "$trimmed" len=${trimmed.length}');

    // ── Helpers (mirrors admin_inventory_stock.dart) ──
    String str(dynamic v) => v?.toString().trim() ?? '';

    String norm(String s) {
      if (RegExp(r'^\d+$').hasMatch(s)) {
        final stripped = s.replaceFirst(RegExp(r'^0+'), '');
        return stripped.isEmpty ? '0' : stripped;
      }
      return s.toLowerCase();
    }

    bool bcMatch(String stored, String scanned) {
      if (stored.isEmpty || scanned.isEmpty) return false;
      if (stored == scanned) return true;
      if (stored.toLowerCase() == scanned.toLowerCase()) return true;
      if (RegExp(r'^\d+$').hasMatch(stored) && RegExp(r'^\d+$').hasMatch(scanned)) {
        final ns = norm(stored), nq = norm(scanned);
        if (ns == nq) return true;
        // Scanned is 1 digit longer (check digit appended by scanner/EAN-13 decode)
        if (nq.length == ns.length + 1 && nq.startsWith(ns)) return true;
        // Stored is 1 digit shorter (stored without check digit, scanned with check digit)
        if (nq.length > ns.length && nq.substring(0, ns.length) == ns) return true;
        // Leading zero differences
        if (ns.length >= 8 && nq.contains(ns)) return true;
        if (nq.length >= 8 && ns.contains(nq)) return true;
        // Leading country code digits
        for (int i = 1; i <= 3 && i < nq.length; i++) {
          if (nq.substring(i) == ns) return true;
          if (nq.substring(i).startsWith(ns)) return true;
        }
      }
      return false;
    }

    // ── Step 1: Full fetch + client-side match (same as admin_inventory_stock.dart) ──
    // Avoids Firestore type mismatches (int vs string) that break direct queries
    Map<String, dynamic>? masterItem;
    List<Map<String, dynamic>> searchResults = [];

    try {
      final all = await FirebaseFirestore.instance.collection('item_master').get();

      DocumentSnapshot? matchDoc;

      // P1: exact barcode string match
      matchDoc = all.docs.cast<DocumentSnapshot?>().firstWhere(
        (d) => str((d!.data() as Map<String, dynamic>)['barcode']) == trimmed,
        orElse: () => null);
      // P2: exact QR string match
      matchDoc ??= all.docs.cast<DocumentSnapshot?>().firstWhere(
        (d) => str((d!.data() as Map<String, dynamic>)['qr']) == trimmed,
        orElse: () => null);
      // P3: normalized barcode/QR match (handles leading zeros, length variants)
      matchDoc ??= all.docs.cast<DocumentSnapshot?>().firstWhere((d) {
        final data = d!.data() as Map<String, dynamic>;
        return bcMatch(str(data['barcode']), trimmed) ||
               bcMatch(str(data['qr']),      trimmed);
      }, orElse: () => null);
      // P4: item number
      matchDoc ??= all.docs.cast<DocumentSnapshot?>().firstWhere(
        (d) => str((d!.data() as Map<String, dynamic>)['num']).toLowerCase() == query,
        orElse: () => null);
      // P5: name contains (non-numeric only)
      if (matchDoc == null && !RegExp(r'^\d+$').hasMatch(trimmed) && query.length >= 3) {
        matchDoc = all.docs.cast<DocumentSnapshot?>().firstWhere(
          (d) => str((d!.data() as Map<String, dynamic>)['name']).toLowerCase().contains(query),
          orElse: () => null);
      }

      if (matchDoc != null) {
        final d = matchDoc.data() as Map<String, dynamic>;
        masterItem = {'id': matchDoc.id, ...d};
        debugPrint('✅ Match: ${d['name']} [bc=${d['barcode']}, qr=${d['qr']}, scanned=$trimmed]');
      } else {
        searchResults = all.docs
            .map((d) => {'id': d.id, ...(d.data() as Map<String, dynamic>)})
            .where((item) =>
                str(item['name']).toLowerCase().contains(query) ||
                bcMatch(str(item['barcode']), trimmed) ||
                bcMatch(str(item['qr']),      trimmed))
            .toList();
        debugPrint('❌ No match for "$trimmed", ${searchResults.length} partial results');
      }
    } catch (e) {
      debugPrint('item_master lookup error: $e');
    }

    if (!mounted) return;

    // ── Step 2: If multiple results, show picker sheet first ──
    if (masterItem == null && searchResults.isNotEmpty) {
      masterItem = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.85,
          builder: (_, ctrl) => Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                color: _red,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Select Item', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('${searchResults.length} results for "$trimmed"',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Expanded(
              child: ListView.separated(
                controller: ctrl,
                padding: const EdgeInsets.all(16),
                itemCount: searchResults.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final item = searchResults[i];
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, item),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)]),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(str(item['name']),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text('${str(item["num"])}  •  ${str(item["group"])}  •  ${str(item["uom"])}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                        ])),
                        const Icon(Icons.chevron_right, size: 18, color: Color(0xFFa0aec0)),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      );
      if (!mounted) return;
    }

    // ── Step 3: Stock + delivery lookup ──
    final resolvedNum  = str(masterItem?['num']).toLowerCase();
    final resolvedName = str(masterItem?['name']).toLowerCase();

    Map<String, dynamic>? stockItem;
    try {
      if (masterItem != null) {
        final snap = await FirebaseFirestore.instance
            .collection('stock_inventory')
            .where('num', isEqualTo: str(masterItem['num']))
            .limit(1).get();
        if (snap.docs.isNotEmpty) {
          final d = snap.docs.first.data() as Map<String, dynamic>;
          final stock = (d['stock'] as num?)?.toInt() ?? 0;
          final min   = (d['min']   as num?)?.toInt() ?? 0;
          final max   = (d['max']   as num?)?.toInt() ?? 0;
          stockItem = {
            'id': snap.docs.first.id, ...d,
            'stock': stock, 'min': min, 'max': max,
            'status': stock > min ? (stock > max ? 'Over' : 'OK') : 'Low',
            'supplierCode': masterItem['supplierCode']?.toString() ?? '',
          };
        }
      }
    } catch (e) {
      debugPrint('stock lookup error: $e');
    }

    Map<String, dynamic>? foundDelivery;
    String? foundItemStatus;
    try {
      final deliveriesSnap = await FirebaseFirestore.instance
          .collection('deliveries').orderBy('createdAt', descending: true).get();
      for (final doc in deliveriesSnap.docs) {
        final d = {...doc.data() as Map<String, dynamic>, 'id': doc.id};
        final deliveryStatus = d['status'] as String? ?? 'Pending';
        if (deliveryStatus == 'Approved' || deliveryStatus == 'Rejected') continue;
        final items = (d['items'] as List? ?? []);
        for (final i in items) {
          final num  = str(i['itemNum']).toLowerCase();
          final name = str(i['itemName']).toLowerCase();
          final matched = (resolvedNum.isNotEmpty && num.contains(resolvedNum)) ||
                 (resolvedName.isNotEmpty && name.contains(resolvedName)) ||
                 num.contains(query) || name.contains(query);
          if (matched) {
            foundDelivery = d;
            foundItemStatus = (i['itemStatus'] as String?) ?? deliveryStatus;
            break;
          }
        }
        if (foundDelivery != null) break;
      }
    } catch (e) {
      debugPrint('delivery lookup error: $e');
    }

    if (!mounted) return;
    _showScanResultModal(context, trimmed, masterItem, stockItem, foundDelivery, foundItemStatus);
  }

  void _showScanResultModal(
    BuildContext context,
    String rawValue,
    Map<String, dynamic>? masterItem,
    Map<String, dynamic>? stockItem,
    Map<String, dynamic>? delivery,
    String? foundItemStatus,
  ) {
    final itemName  = masterItem?['name']?.toString()  ?? rawValue;
    final itemNum   = masterItem?['num']?.toString()   ?? '—';
    final itemGroup = masterItem?['group']?.toString() ?? '';
    final itemUom   = masterItem?['uom']?.toString()   ?? '';
    final itemCost  = masterItem?['cost']?.toString()  ?? '';
    final itemType  = masterItem?['type']?.toString()  ?? '';
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
                  if (itemUom.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(itemUom, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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

                // Item not found warning — but still show actions
                if (masterItem == null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFD54F), width: 1.5)),
                    child: Row(children: [
                      const Icon(Icons.info_outline, size: 16, color: Color(0xFFd69e2e)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'Item not found for "$rawValue". You can still navigate below.',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF92400E)))),
                    ]),
                  ),
                  const SizedBox(height: 14),
                ],

                const Text('What would you like to do?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c))),
                const SizedBox(height: 12),

                // Option 1: View Stock (only if matched item is in stock)
                if (masterItem != null && isMaterial && stockItem != null) ...[
                  _actionTile(
                    context: context,
                    icon: Icons.inventory_2_outlined,
                    iconColor: const Color(0xFF003087),
                    iconBg: const Color(0xFFEBF8FF),
                    title: 'View Stock',
                    subtitle: 'Current: ${stockItem['stock']}',
                    onTap: () {
                      Navigator.pop(context);
                      _showStockDetailModal(context, stockItem);
                    },
                  ),
                  const SizedBox(height: 10),
                ],

                // Option 2: Receive from delivery
                if (delivery != null) ...[
                  Builder(builder: (_) {
                    final isPending = foundItemStatus == 'Pending';
                    return _actionTile(
                      context: context,
                      icon: Icons.download_outlined,
                      iconColor: isPending ? const Color(0xFF38a169) : const Color(0xFFa0aec0),
                      iconBg: isPending ? const Color(0xFFF0FFF4) : const Color(0xFFF7F8FA),
                      title: 'Receive Items',
                      subtitle: isPending
                          ? 'From pending delivery'
                          : 'Item is $foundItemStatus — cannot receive',
                      badge: foundItemStatus ?? 'Pending',
                      badgeColor: isPending ? const Color(0xFF718096) : const Color(0xFFd69e2e),
                      onTap: isPending
                          ? () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => _ReceivingWithModal(delivery: delivery)));
                            }
                          : null,
                    );
                  }),
                  const SizedBox(height: 10),
                ],

                // Option 3: Use in Maintenance
                _actionTile(
                  context: context,
                  icon: Icons.build_outlined,
                  iconColor: const Color(0xFFd69e2e),
                  iconBg: const Color(0xFFFFFBEB),
                  title: 'Use in Maintenance',
                  subtitle: masterItem != null
                      ? 'Add ${masterItem['name'] ?? ''} to a maintenance record'
                      : 'Add to a vehicle maintenance record',
                  onTap: () {
                    Navigator.pop(context);
                    final matData = {
                      'name': masterItem?['name']?.toString() ?? rawValue,
                      'num':  masterItem?['num']?.toString()  ?? '',
                      'uom':  masterItem?['uom']?.toString()  ?? '',
                      'cost': masterItem?['cost']?.toString() ?? '0',
                    };
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AdminVehicleMaintenance(materialData: matData)));
                  },
                ),
                const SizedBox(height: 10),


              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Receive Items modal (mirrors AdminReceivingBodyState._showReceiveModal) ──
  static const _green = Color(0xFF38a169);
  static const _amber = Color(0xFFd69e2e);
  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  String _fmtDate(String? d) {
    if (d == null || d.isEmpty) return '—';
    final dt = DateTime.tryParse(d);
    if (dt != null) return '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
    return d;
  }

  void _showReceiveModal(BuildContext context, Map<String, dynamic> delivery) async {
    String currentUserName = '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      currentUserName = (doc.data()?['name'] as String?) ?? '';
    }
    if (!mounted) return;

    final items = List<Map<String, dynamic>>.from(
      (delivery['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)),
    );
    final receivedByCtrl = TextEditingController(text: currentUserName);
    final qtyCtrlrs = List.generate(items.length, (i) =>
        TextEditingController(text: '${items[i]['expectedQty'] ?? 0}'));
    final conditionList = List<String>.filled(items.length, 'OK');
    final remarkCtrlrs = List.generate(items.length, (_) => TextEditingController());
    bool submitting = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => DraggableScrollableSheet(
          expand: false, initialChildSize: 0.92, maxChildSize: 0.97,
          builder: (_, ctrl) => SingleChildScrollView(
            controller: ctrl,
            child: Column(children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(
                  color: _red,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  Expanded(child: const Text('Receive Items',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                  GestureDetector(onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              // Step indicator
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  _rcvStep('1', 'Input Quantities', active: true),
                  const Expanded(child: Divider()),
                  _rcvStep('2', 'Awaiting Check'),
                  const Expanded(child: Divider()),
                  _rcvStep('3', 'Approved'),
                ]),
              ),
              Padding(
                padding: EdgeInsets.only(left: 20, right: 20, top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ...items.asMap().entries.map((e) {
                    final i = e.key;
                    final item = e.value;
                    final expected = item['expectedQty'] as int? ?? 0;
                    return _rcvItemCard(
                      index: i, item: item, expected: expected,
                      qtyCtrl: qtyCtrlrs[i],
                      remarkCtrl: remarkCtrlrs[i],
                      condition: conditionList[i],
                      onCondChange: (c) => setModal(() => conditionList[i] = c),
                      onQtyChange: () => setModal(() {}),
                    );
                  }),
                  const SizedBox(height: 12),
                  // Received By (read-only display)
                  const Text('Received By',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFe2e8f0)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.person_outline, size: 16, color: Color(0xFF718096)),
                      const SizedBox(width: 8),
                      Text(receivedByCtrl.text.isNotEmpty ? receivedByCtrl.text : '—',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: submitting ? null : () async {
                        if (receivedByCtrl.text.trim().isEmpty) return;
                        setModal(() => submitting = true);
                        final updatedItems = items.asMap().entries.map((e) {
                          final i = e.key;
                          return {
                            ...e.value,
                            'actualQty': int.tryParse(qtyCtrlrs[i].text) ?? e.value['expectedQty'],
                            'condition': conditionList[i],
                            'remark': remarkCtrlrs[i].text.trim(),
                          };
                        }).toList();
                        try {
                          await FirebaseFirestore.instance
                              .collection('deliveries')
                              .doc(delivery['id'] as String)
                              .update({
                            'items': updatedItems,
                            'receivedBy': receivedByCtrl.text.trim(),
                            'status': 'Awaiting Double Check',
                            'receivedAt': FieldValue.serverTimestamp(),
                          });
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Submitted for double check!'),
                              backgroundColor: Colors.orange,
                              behavior: SnackBarBehavior.floating));
                          }
                        } catch (err) {
                          setModal(() => submitting = false);
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red));
                        }
                      },
                      icon: submitting
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline, size: 16),
                      label: Text(submitting ? 'Submitting…' : 'Submit for Double Check'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _red, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _rcvStep(String num, String label, {bool active = false}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: active ? _red : const Color(0xFFe2e8f0),
          shape: BoxShape.circle),
        child: Center(child: Text(num,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF718096),
            fontWeight: FontWeight.w700, fontSize: 11)))),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 8, color: Color(0xFF718096)), textAlign: TextAlign.center),
    ],
  );

  Widget _rcvItemCard({
    required int index, required Map<String, dynamic> item, required int expected,
    required TextEditingController qtyCtrl, required TextEditingController remarkCtrl,
    required String condition, required ValueChanged<String> onCondChange,
    required VoidCallback onQtyChange,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF90cdf4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item['itemName'] as String? ?? '—',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        Text('${item['itemNum'] ?? ''} · Expected: $expected ${item['uom'] ?? ''}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
        const SizedBox(height: 10),
        TextField(
          controller: qtyCtrl, keyboardType: TextInputType.number,
          onChanged: (_) => onQtyChange(),
          decoration: InputDecoration(
            labelText: 'Actual Qty *', border: const OutlineInputBorder(), isDense: true,
            suffixText: item['uom'] as String? ?? ''),
        ),
        const SizedBox(height: 10),
        const Text('Condition', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
        const SizedBox(height: 6),
        Row(children: [
          _rcvCondBtn('✅ OK',        'OK',        condition, onCondChange),
          const SizedBox(width: 6),
          _rcvCondBtn('❌ Defective', 'Defective', condition, onCondChange),
          const SizedBox(width: 6),
          _rcvCondBtn('⚠️ Shortage', 'Shortage',  condition, onCondChange),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: remarkCtrl,
          decoration: const InputDecoration(
            labelText: 'Remarks (optional)', border: OutlineInputBorder(), isDense: true,
            hintText: 'e.g. 1 unit damaged packaging')),
      ]),
    );
  }

  Widget _rcvCondBtn(String label, String value, String current, ValueChanged<String> onChange) {
    final active = current == value;
    Color color;
    switch (value) {
      case 'OK':        color = _green; break;
      case 'Defective': color = _red;   break;
      default:          color = _amber;
    }
    return GestureDetector(
      onTap: () => onChange(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? color : const Color(0xFFe2e8f0), width: 1.5)),
        child: Text(label, style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: active ? color : const Color(0xFF718096)))),
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
    final status     = item['status']?.toString() ?? 'OK';
    final stock      = (item['stock'] as num?)?.toInt() ?? 0;
    final min        = (item['min']   as num?)?.toInt() ?? 0;
    final max        = (item['max']   as num?)?.toInt() ?? 0;
    final isOut      = stock == 0;
    final isLow      = !isOut && status == 'Low';
    final isOver     = !isOut && !isLow && status == 'Over';
    final progress   = max > 0 ? (stock / max).clamp(0.0, 1.0) : 0.0;
    final barColor   = isOut ? Colors.red : isLow ? Colors.orange : isOver ? Colors.purple : Colors.green;
    final statusLabel = isOut ? 'Out of Stock' : isLow ? 'Low Stock' : isOver ? 'Over Max' : 'In Stock';

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
            // Header — item name + UOM subtitle
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                  color: _red,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item['name']?.toString() ?? '—',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(item['uom']?.toString() ?? '',
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
                    color: isOut
                        ? Colors.red.shade50
                        : isLow
                            ? Colors.orange.shade50
                            : const Color(0xFFF0FFF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOut
                          ? Colors.red.shade200
                          : isLow
                              ? Colors.orange.shade200
                              : const Color(0xFF9AE6B4)),
                  ),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('$stock',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: barColor)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: barColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20)),
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
                // Detail rows — same as admin_inventory_stock _showStockDetails
                if ((item['supplierCode']?.toString() ?? '').isNotEmpty)
                  _detailRowInline('Supplier Item Code', item['supplierCode']?.toString() ?? '—'),
                _detailRowInline('Item Number',     item['num']?.toString()   ?? '—'),
                _detailRowInline('Item Name',       item['name']?.toString()  ?? '—'),
                _detailRowInline('Commodity Group', item['group']?.toString() ?? '—'),
                _detailRowInline('UOM',             item['uom']?.toString()   ?? '—'),
                _detailRowInline('Current Stock',   '$stock'),
                _detailRowInline('Min Level',       '$min'),
                _detailRowInline('Max Level',       '$max'),
                _detailRowInline('Reorder Qty',     '${(item['reorder'] as num?)?.toInt() ?? 0}'),
                _detailRowInline('Status',          isOut ? 'Out of Stock' : isLow ? 'Low Stock' : isOver ? 'Over Max' : 'In Stock'),
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

// ── Receiving page wrapper that auto-opens the receive modal ────────────────
class _ReceivingWithModal extends StatefulWidget {
  final Map<String, dynamic> delivery;
  const _ReceivingWithModal({required this.delivery});

  @override
  State<_ReceivingWithModal> createState() => _ReceivingWithModalState();
}

class _ReceivingWithModalState extends State<_ReceivingWithModal> {
  static const _red = Color(0xFFE8001C);
  final _bodyKey = GlobalKey<AdminReceivingBodyState>();

  @override
  void initState() {
    super.initState();
    // Open the receive modal as soon as the page is laid out
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bodyKey.currentState?.openReceiveModal(widget.delivery);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Receiving',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: AdminReceivingBody(key: _bodyKey),
    );
  }
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
