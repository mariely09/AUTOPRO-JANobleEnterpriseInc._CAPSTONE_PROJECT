import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'barcode_scanner_screen.dart';
import 'admin_vehicle_maintenance.dart';
import 'staff_receiving.dart';
import 'receiving_item_modals.dart';

/// Reusable bottom navigation bar for Staff Dashboard.
/// Handles tab switching and the center scanner button with full scan functionality.
class StaffBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  static const Color _red = Color(0xFFE8001C);

  const StaffBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  @override
  State<StaffBottomNavBar> createState() => _StaffBottomNavBarState();
}

class _StaffBottomNavBarState extends State<StaffBottomNavBar> {
  static const _red = Color(0xFFE8001C);

  static const List<_NavItem> navItems = [
    _NavItem(icon: Icons.dashboard_outlined, label: 'Dashboard'),
    _NavItem(icon: Icons.inventory_2_outlined, label: 'Inventory'),
    _NavItem(icon: Icons.directions_car_outlined, label: 'Assets'),
    _NavItem(icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 4 slots: 2 left + center placeholder + 2 right
              Row(
                children: [
                  _navBtn(0), // Dashboard
                  _navBtn(1), // Inventory
                  const Expanded(
                    child: SizedBox(),
                  ), // center placeholder for scan button
                  _navBtn(2), // Vehicle
                  _navBtn(3), // Profile
                ],
              ),
              // Center scan button
              Positioned(
                top: -20,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _showScanModal,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _red.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 26,
                      ),
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

  Widget _navBtn(int i) {
    final active = widget.currentIndex == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onIndexChanged(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              navItems[i].icon,
              color: active ? _red : const Color(0xFF718096),
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              navItems[i].label,
              style: TextStyle(
                fontSize: 10,
                color: active ? _red : const Color(0xFF718096),
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Barcode / QR scanner modal — mirrors AdminBottomNavBar functionality ──
  void _showScanModal() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (result == null || !mounted) return;

    final trimmed = result.trim();
    final query = trimmed.toLowerCase();
    debugPrint('🔍 Staff Scanned: "$trimmed" len=${trimmed.length}');

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
      if (RegExp(r'^\d+$').hasMatch(stored) &&
          RegExp(r'^\d+$').hasMatch(scanned)) {
        final ns = norm(stored), nq = norm(scanned);
        if (ns == nq) return true;
        if (nq.length == ns.length + 1 && nq.startsWith(ns)) return true;
        if (nq.length > ns.length && nq.substring(0, ns.length) == ns)
          return true;
        if (ns.length >= 8 && nq.contains(ns)) return true;
        if (nq.length >= 8 && ns.contains(nq)) return true;
        for (int i = 1; i <= 3 && i < nq.length; i++) {
          if (nq.substring(i) == ns) return true;
          if (nq.substring(i).startsWith(ns)) return true;
        }
      }
      return false;
    }

    // ── Step 1: Full fetch + client-side match ──
    Map<String, dynamic>? masterItem;
    List<Map<String, dynamic>> searchResults = [];

    try {
      final all = await FirebaseFirestore.instance
          .collection('item_master')
          .get();

      DocumentSnapshot? matchDoc;

      // P1: exact barcode string match
      matchDoc = all.docs.cast<DocumentSnapshot?>().firstWhere(
        (d) => str((d!.data() as Map<String, dynamic>)['barcode']) == trimmed,
        orElse: () => null,
      );
      // P2: exact QR string match
      matchDoc ??= all.docs.cast<DocumentSnapshot?>().firstWhere(
        (d) => str((d!.data() as Map<String, dynamic>)['qr']) == trimmed,
        orElse: () => null,
      );
      // P3: normalized barcode/QR match
      matchDoc ??= all.docs.cast<DocumentSnapshot?>().firstWhere((d) {
        final data = d!.data() as Map<String, dynamic>;
        return bcMatch(str(data['barcode']), trimmed) ||
            bcMatch(str(data['qr']), trimmed);
      }, orElse: () => null);
      // P4: item number
      matchDoc ??= all.docs.cast<DocumentSnapshot?>().firstWhere(
        (d) =>
            str((d!.data() as Map<String, dynamic>)['num']).toLowerCase() ==
            query,
        orElse: () => null,
      );
      // P5: name contains (non-numeric only)
      if (matchDoc == null &&
          !RegExp(r'^\d+$').hasMatch(trimmed) &&
          query.length >= 3) {
        matchDoc = all.docs.cast<DocumentSnapshot?>().firstWhere(
          (d) => str(
            (d!.data() as Map<String, dynamic>)['name'],
          ).toLowerCase().contains(query),
          orElse: () => null,
        );
      }

      if (matchDoc != null) {
        final d = matchDoc.data() as Map<String, dynamic>;
        masterItem = {'id': matchDoc.id, ...d};
        debugPrint(
          '✅ Match: ${d['name']} [bc=${d['barcode']}, qr=${d['qr']}, scanned=$trimmed]',
        );
      } else {
        searchResults = all.docs
            .map((d) => {'id': d.id, ...d.data()})
            .where(
              (item) =>
                  str(item['name']).toLowerCase().contains(query) ||
                  bcMatch(str(item['barcode']), trimmed) ||
                  bcMatch(str(item['qr']), trimmed),
            )
            .toList();
        debugPrint(
          '❌ No match for "$trimmed", ${searchResults.length} partial results',
        );
      }
    } catch (e) {
      debugPrint('item_master lookup error: $e');
    }

    if (!mounted) return;

    // ── Step 2: If multiple results, show picker sheet ──
    if (masterItem == null && searchResults.isNotEmpty) {
      masterItem = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.85,
          builder: (_, ctrl) => Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(
                  color: _red,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Item',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${searchResults.length} results for "$trimmed"',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: ctrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: searchResults.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 8),
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
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    str(item['name']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${str(item["num"])}  •  ${str(item["group"])}  •  ${str(item["uom"])}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF718096),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: Color(0xFFa0aec0),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
    }

    // ── Step 3: Stock + delivery lookup ──
    final resolvedNum = str(masterItem?['num']).toLowerCase();
    final resolvedName = str(masterItem?['name']).toLowerCase();

    Map<String, dynamic>? stockItem;
    try {
      if (masterItem != null) {
        final snap = await FirebaseFirestore.instance
            .collection('stock_inventory')
            .where('num', isEqualTo: str(masterItem['num']))
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final d = snap.docs.first.data();
          final stock = (d['stock'] as num?)?.toInt() ?? 0;
          final min = (d['min'] as num?)?.toInt() ?? 0;
          final max = (d['max'] as num?)?.toInt() ?? 0;
          stockItem = {
            'id': snap.docs.first.id,
            ...d,
            'stock': stock,
            'min': min,
            'max': max,
            'status': stock > min ? (stock > max ? 'Over' : 'OK') : 'Low',
            'supplierCode': masterItem['supplierCode']?.toString() ?? '',
          };
        }
      }
    } catch (e) {
      debugPrint('stock lookup error: $e');
    }

    Map<String, dynamic>? foundReceiving;
    String? foundItemStatus;
    int foundItemIdx = -1;
    try {
      final receivingsSnap = await FirebaseFirestore.instance
          .collection('receivings')
          .orderBy('createdAt', descending: true)
          .get();
      for (final doc in receivingsSnap.docs) {
        final d = {...doc.data(), 'id': doc.id};
        final rcvStatus = d['status'] as String? ?? 'DRAFT';
        if (rcvStatus == 'COMP' || rcvStatus == 'PARTIAL') continue;
        final lines = (d['receivingLines'] as List? ?? []);
        for (int idx = 0; idx < lines.length; idx++) {
          final line = lines[idx];
          final num = str(line['itemNum']).toLowerCase();
          final name = str(line['itemName']).toLowerCase();
          final matched =
              (resolvedNum.isNotEmpty && num.contains(resolvedNum)) ||
              (resolvedName.isNotEmpty && name.contains(resolvedName)) ||
              num.contains(query) ||
              name.contains(query);
          if (matched) {
            foundReceiving = d;
            foundItemStatus = (line['lineStatus'] as String?) ?? 'DRAFT';
            foundItemIdx = idx;
            break;
          }
        }
        if (foundReceiving != null) break;
      }
    } catch (e) {
      debugPrint('receiving lookup error: $e');
    }

    if (!mounted) return;
    _showScanResultModal(
      context,
      trimmed,
      masterItem,
      stockItem,
      foundReceiving,
      foundItemStatus,
      foundItemIdx,
    );
  }

  void _showScanResultModal(
    BuildContext context,
    String rawValue,
    Map<String, dynamic>? masterItem,
    Map<String, dynamic>? stockItem,
    Map<String, dynamic>? receiving,
    String? foundItemStatus, [
    int foundItemIdx = -1,
  ]) {
    final itemName = masterItem?['name']?.toString() ?? rawValue;
    final itemUom = masterItem?['uom']?.toString() ?? '';
    final itemType = masterItem?['type']?.toString() ?? '';
    final isMaterial = itemType == 'Material' || masterItem == null;

    String str(dynamic v) => v?.toString().trim() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE8001C), Color(0xFFa50014)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            itemName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (itemUom.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              itemUom,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Item not found warning
                    if (masterItem == null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFFFD54F),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Color(0xFFd69e2e),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Item not found for "$rawValue". You can still navigate below.',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    const Text(
                      'What would you like to do?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1a202c),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Option 1: View Stock (only if matched item is in stock)
                    if (masterItem != null &&
                        isMaterial &&
                        stockItem != null) ...[
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

                    // Option 2: Receive from receiving
                    if (receiving != null) ...[
                      Builder(
                        builder: (_) {
                          final isDraft = foundItemStatus == 'DRAFT';
                          return _actionTile(
                            context: context,
                            icon: Icons.download_outlined,
                            iconColor: isDraft
                                ? const Color(0xFF38a169)
                                : const Color(0xFFa0aec0),
                            iconBg: isDraft
                                ? const Color(0xFFF0FFF4)
                                : const Color(0xFFF7F8FA),
                            title: 'Receive Items',
                            subtitle: isDraft
                                ? 'Tap to receive this item now'
                                : 'Item is $foundItemStatus — already received',
                            badge: foundItemStatus ?? 'DRAFT',
                            badgeColor: isDraft
                                ? const Color(0xFF718096)
                                : const Color(0xFFd69e2e),
                            onTap: isDraft
                                ? () {
                                    Navigator.pop(context);
                                    // Directly open receive modal
                                    _showReceiveModal(
                                      context,
                                      receiving,
                                      foundItemIdx,
                                    );
                                  }
                                : null,
                          );
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
                      subtitle: masterItem != null
                          ? 'Add ${masterItem['name'] ?? ''} to a maintenance record'
                          : 'Add to a vehicle maintenance record',
                      onTap: () {
                        Navigator.pop(context);
                        final matData = {
                          'name': masterItem?['name']?.toString() ?? rawValue,
                          'num': masterItem?['num']?.toString() ?? '',
                          'uom': masterItem?['uom']?.toString() ?? '',
                          'cost': masterItem?['cost']?.toString() ?? '0',
                        };
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AdminVehicleMaintenance(materialData: matData),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: disabled
                          ? const Color(0xFFa0aec0)
                          : const Color(0xFF1a202c),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: disabled
                          ? const Color(0xFFcbd5e0)
                          : const Color(0xFF718096),
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (badgeColor ?? const Color(0xFF718096)).withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: badgeColor ?? const Color(0xFF718096),
                  ),
                ),
              ),
            ] else if (!disabled)
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xFFa0aec0),
              ),
          ],
        ),
      ),
    );
  }

  void _showStockDetailModal(BuildContext context, Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? 'OK';
    final stock = (item['stock'] as num?)?.toInt() ?? 0;
    final min = (item['min'] as num?)?.toInt() ?? 0;
    final max = (item['max'] as num?)?.toInt() ?? 0;
    final isOut = stock == 0;
    final isLow = !isOut && status == 'Low';
    final isOver = !isOut && !isLow && status == 'Over';
    final barColor = isOut
        ? Colors.red
        : isLow
        ? Colors.orange
        : isOver
        ? Colors.purple
        : Colors.green;
    final statusLabel = isOut
        ? 'Out of Stock'
        : isLow
        ? 'Low Stock'
        : isOver
        ? 'Over Max'
        : 'In Stock';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.88,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                decoration: const BoxDecoration(
                  color: _red,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name']?.toString() ?? '—',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            item['uom']?.toString() ?? '',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                              : const Color(0xFF9AE6B4),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$stock',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: barColor,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: barColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: barColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Detail rows
                    if ((item['supplierCode']?.toString() ?? '').isNotEmpty)
                      _detailRowInline(
                        'Supplier Item Code',
                        item['supplierCode']?.toString() ?? '—',
                      ),
                    _detailRowInline(
                      'Item Number',
                      item['num']?.toString() ?? '—',
                    ),
                    _detailRowInline(
                      'Item Name',
                      item['name']?.toString() ?? '—',
                    ),
                    _detailRowInline(
                      'Commodity Group',
                      item['group']?.toString() ?? '—',
                    ),
                    _detailRowInline('UOM', item['uom']?.toString() ?? '—'),
                    _detailRowInline('Current Stock', '$stock'),
                    _detailRowInline('Min Level', '$min'),
                    _detailRowInline('Max Level', '$max'),
                    _detailRowInline(
                      'Reorder Qty',
                      '${(item['reorder'] as num?)?.toInt() ?? 0}',
                    ),
                    _detailRowInline(
                      'Status',
                      isOut
                          ? 'Out of Stock'
                          : isLow
                          ? 'Low Stock'
                          : isOver
                          ? 'Over Max'
                          : 'In Stock',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRowInline(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF718096),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1a202c),
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Direct receive modal (opens receive item modal from scan result) ─────
void _showReceiveModal(
  BuildContext context,
  Map<String, dynamic> receiving,
  int lineIdx,
) {
  // Open the line view modal which has the "Receive" button
  showLineViewModal(
    context,
    rcvData: receiving,
    lineIdx: lineIdx,
    isBlank: (receiving['poNum'] as String?)?.isEmpty ?? true,
    onReceive: () async {
      // Callback after receiving - no action needed as modal handles refresh
    },
  );
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem({required this.icon, required this.label});
}

// ── Receiving page wrapper (navigated to from scan result) ─────────────────
class _ReceivingWithModal extends StatefulWidget {
  final Map<String, dynamic> receiving;
  final int itemIdx;
  const _ReceivingWithModal({required this.receiving, this.itemIdx = -1});

  @override
  State<_ReceivingWithModal> createState() => _ReceivingWithModalState();
}

class _ReceivingWithModalState extends State<_ReceivingWithModal> {
  static const _red = Color(0xFFE8001C);
  final _bodyKey = GlobalKey<State<StaffReceivingBody>>();

  @override
  void initState() {
    super.initState();
    // Users can find their record in the Receiving list
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Receiving',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: StaffReceivingBody(key: _bodyKey),
    );
  }
}
