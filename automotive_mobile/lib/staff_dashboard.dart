import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart';
import 'profile.dart';
import 'staff_inventory.dart';
import 'staff_maintenance.dart';
import 'staff_vehicle_list.dart';
import 'notifications.dart';
import 'barcode_scanner_screen.dart';
import 'staff_bottomnavbar.dart';
import 'staff_calendar_widget.dart';

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  int _currentIndex = 0;
  static const _red = Color(0xFFE8001C);
  static const _bg = Color(0xFFF7F8FA);
  String _initials = '?';
  String? _photoUrl;
  String _staffName = '';

  @override
  void initState() {
    super.initState();
    _loadInitials();
  }

  Future<void> _loadInitials() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    final name = data['name'] as String? ?? '';
    final photo = data['photoUrl'] as String?;
    if (name.isEmpty && photo == null) return;
    String ini = '?';
    if (name.isNotEmpty) {
      final parts = name.trim().split(' ');
      ini = parts.length >= 2
          ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
          : parts[0][0].toUpperCase();
    }
    if (mounted) setState(() { _initials = ini; _photoUrl = photo; _staffName = name; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildTopBar(),
      body: Stack(
        children: [
          _buildBody(),
          // Floating calendar — only shown on the dashboard tab
          if (_currentIndex == 0) const StaffCalendarFloating(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildTopBar() {
    return AppBar(
      backgroundColor: _red,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserProfile(role: UserRole.staff)))
                .then((_) => _loadInitials()),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
              child: _photoUrl == null
                  ? Text(_initials, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(_staffName.isNotEmpty ? _staffName : 'Staff Portal',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: NotifBadge(
            role: NotificationRole.staff,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppNotifications(role: NotificationRole.staff))),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody() {
    // Only dashboard renders inline; other tabs navigate to their own pages
    return _buildDashboard();
  }

  Widget _buildBottomNav() {
    return StaffBottomNavBar(
      currentIndex: _currentIndex,
      onIndexChanged: (index) {
        if (index == 0) {
          setState(() => _currentIndex = 0);
        } else if (index == 1) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffInventory()));
        } else if (index == 2) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffVehicleList()));
        } else if (index == 3) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const UserProfile(role: UserRole.staff)))
              .then((_) => _loadInitials());
        }
      },
      onScanPressed: _showScanModal,
    );
  }

  void _showScanModal() async {
    final result = await Navigator.push<String>(context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
    if (result == null || !mounted) return;

    final trimmed = result.trim();
    final query   = trimmed.toLowerCase();

    // ── Barcode/QR match helpers ──
    String _norm(String s) {
      final t = s.trim();
      if (RegExp(r'^\d+$').hasMatch(t)) {
        final stripped = t.replaceFirst(RegExp(r'^0+'), '');
        return stripped.isEmpty ? '0' : stripped;
      }
      return t.toLowerCase();
    }

    bool _match(String stored, String scanned) {
      if (stored.isEmpty || scanned.isEmpty) return false;
      if (stored == scanned) return true;
      if (stored.toLowerCase() == scanned.toLowerCase()) return true;
      final sNum = RegExp(r'^\d+$').hasMatch(stored.trim());
      final qNum = RegExp(r'^\d+$').hasMatch(scanned.trim());
      if (sNum && qNum) {
        final ns = _norm(stored), nq = _norm(scanned);
        if (ns == nq) return true;
        if (ns.length >= 10 && nq.length > ns.length && nq.contains(ns)) return true;
        if (nq.length == ns.length + 1 && nq.startsWith(ns)) return true;
        for (int i = 1; i <= 3 && i < nq.length; i++) {
          if (nq.substring(i) == ns) return true;
        }
      }
      return false;
    }

    // Step 1: Resolve barcode/QR/num → item via item_master
    Map<String, dynamic>? masterItem;
    String resolvedNum  = '';
    String resolvedName = '';

    try {
      final all = await FirebaseFirestore.instance.collection('item_master').get();

      DocumentSnapshot? matchDoc;

      // P1: exact barcode
      matchDoc = all.docs.cast<DocumentSnapshot?>().firstWhere(
        (d) => (d!.data() as Map<String, dynamic>)['barcode']?.toString().trim() == trimmed,
        orElse: () => null);
      // P2: exact QR
      matchDoc ??= all.docs.cast<DocumentSnapshot?>().firstWhere(
        (d) => (d!.data() as Map<String, dynamic>)['qr']?.toString().trim() == trimmed,
        orElse: () => null);
      // P3: normalized barcode/QR
      matchDoc ??= all.docs.cast<DocumentSnapshot?>().firstWhere((d) {
        final data = d!.data() as Map<String, dynamic>;
        return _match(data['barcode']?.toString() ?? '', trimmed) ||
               _match(data['qr']?.toString()      ?? '', trimmed);
      }, orElse: () => null);
      // P4: item number
      matchDoc ??= all.docs.cast<DocumentSnapshot?>().firstWhere(
        (d) => (d!.data() as Map<String, dynamic>)['num']?.toString().trim().toLowerCase() == trimmed.toLowerCase(),
        orElse: () => null);
      // P5: name (non-numeric query only)
      if (matchDoc == null && query.length >= 3 && !RegExp(r'^\d+$').hasMatch(trimmed)) {
        matchDoc = all.docs.cast<DocumentSnapshot?>().firstWhere(
          (d) => ((d!.data() as Map<String, dynamic>)['name']?.toString() ?? '').toLowerCase().contains(query),
          orElse: () => null);
      }

      if (matchDoc != null) {
        final d = matchDoc.data() as Map<String, dynamic>;
        resolvedNum  = (d['num']?.toString()  ?? '').toLowerCase();
        resolvedName = (d['name']?.toString() ?? '').toLowerCase();
        masterItem   = {'id': matchDoc.id, ...d};
        debugPrint('✅ item_master match: ${d['name']} [barcode=${d['barcode']}, scanned=$trimmed]');
      } else {
        debugPrint('❌ No match for scanned: "$trimmed"');
      }
    } catch (e) {
      debugPrint('item_master lookup error: $e');
    }

    if (!mounted) return;

    // Step 2: Find matching pending delivery
    Map<String, dynamic>? foundDelivery;
    try {
      final deliveriesSnap = await FirebaseFirestore.instance
          .collection('deliveries')
          .where('status', isEqualTo: 'Pending')
          .get();

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

    if (!mounted) return;

    // Step 3: Always show modal — even if nothing was found
    _showScanResultModal(
      rawValue:   trimmed,
      masterItem: masterItem,
      delivery:   foundDelivery,
    );
  }

  void _showScanResultModal({
    required String rawValue,
    required Map<String, dynamic>? masterItem,
    required Map<String, dynamic>? delivery,
  }) {
    final itemName  = masterItem?['name'] as String? ?? rawValue;
    final itemNum   = masterItem?['num']  as String? ?? '—';
    final itemGroup = masterItem?['group'] as String? ?? '';
    final itemUom   = masterItem?['uom']  as String? ?? '';
    final itemCost  = masterItem?['cost'] as String? ?? '';
    final itemType  = masterItem?['type'] as String? ?? '';
    final isMaterial = (masterItem?['type'] as String? ?? '') == 'Material';

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
            // ── Header ────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE8001C), Color(0xFFa50014)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
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
                // ── Item chips ───────────────────────────────────────────
                if (masterItem != null && (itemUom.isNotEmpty || itemCost.isNotEmpty || itemType.isNotEmpty)) ...[
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (itemUom.isNotEmpty)
                      _infoBadge(Icons.straighten_outlined, itemUom,  const Color(0xFF003087)),
                    if (itemCost.isNotEmpty)
                      _infoBadge(Icons.attach_money,        itemCost, const Color(0xFF38a169)),
                    if (itemType.isNotEmpty)
                      _infoBadge(Icons.category_outlined,   itemType, const Color(0xFFd69e2e)),
                  ]),
                  const SizedBox(height: 20),
                ],

                // ── Item not found ───────────────────────────────────────
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
                  // ── Section title ────────────────────────────────────────
                  const Text('What would you like to do?',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c))),
                  const SizedBox(height: 12),

                  // ── Option 1: Receive Items (only if pending delivery exists) ──
                  if (delivery != null) ...[
                    _actionTile(
                      icon: Icons.download_outlined,
                      iconColor: const Color(0xFF38a169),
                      iconBg: const Color(0xFFF0FFF4),
                      title: 'Receive Items',
                      subtitle: 'From delivery by ${delivery['supplier']}',
                      badge: 'Pending',
                      badgeColor: const Color(0xFF718096),
                      onTap: () {
                        Navigator.pop(context);
                        _showReceiveFromDashboard(delivery);
                      },
                    ),
                    const SizedBox(height: 10),
                  ] else ...[
                    // No pending delivery — greyed out tile
                    _actionTile(
                      icon: Icons.download_outlined,
                      iconColor: const Color(0xFFa0aec0),
                      iconBg: const Color(0xFFF7F8FA),
                      title: 'Receive Items',
                      subtitle: 'No pending delivery found for this item',
                      onTap: null,
                    ),
                    const SizedBox(height: 10),
                  ],

                  // ── Option 2: View Stock ─────────────────────────────────
                  if (isMaterial)
                    _actionTile(
                      icon: Icons.inventory_2_outlined,
                      iconColor: const Color(0xFF003087),
                      iconBg: const Color(0xFFEBF8FF),
                      title: 'View Stock',
                      subtitle: 'Check current inventory levels',
                      onTap: () {
                        Navigator.pop(context);
                        _showStockDetailFromScan(masterItem!);
                      },
                    ),

                  if (isMaterial) const SizedBox(height: 10),

                  // ── Option 3: Use in Maintenance ─────────────────────────
                  _actionTile(
                    icon: Icons.build_outlined,
                    iconColor: const Color(0xFFd69e2e),
                    iconBg: const Color(0xFFFFFBEB),
                    title: 'Use in Maintenance',
                    subtitle: 'Add to a service / maintenance record',
                    onTap: () {
                      Navigator.pop(context);
                      // Build materialData map from masterItem
                      final matData = {
                        'name': masterItem!['name'] as String? ?? '',
                        'num':  masterItem!['num']  as String? ?? '',
                        'uom':  masterItem!['uom']  as String? ?? '',
                        'cost': masterItem!['cost'] as String? ?? '0',
                      };
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => StaffMaintenance(materialData: matData)));
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

  Widget _actionTile({
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

  // ── Inline receive modal (called from scan result modal) ──────────────────
  void _showReceiveFromDashboard(Map<String, dynamic> delivery) async {
    const red   = Color(0xFFE8001C);
    const amber = Color(0xFFd69e2e);
    const green = Color(0xFF38a169);
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    String fmt(String? d) {
      if (d == null || d.isEmpty) return '—';
      final dt = DateTime.tryParse(d);
      if (dt != null) return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
      return d;
    }

    String currentUserName = '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      currentUserName = (doc.data()?['name'] as String?) ?? '';
    }
    if (!mounted) return;

    final items = List<Map<String, dynamic>>.from(
      (delivery['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)));
    final receivedByCtrl = TextEditingController(text: currentUserName);
    final qtyCtrlrs = List.generate(items.length, (i) =>
        TextEditingController(text: '${items[i]['expectedQty'] ?? 0}'));
    final conditionList = List<String>.filled(items.length, 'OK');
    final remarkCtrlrs = List.generate(items.length, (_) => TextEditingController());

    Widget step(String num, String label, {bool active = false}) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            color: active ? red : const Color(0xFFe2e8f0), shape: BoxShape.circle),
          child: Center(child: Text(num, style: TextStyle(
            color: active ? Colors.white : const Color(0xFF718096),
            fontWeight: FontWeight.w700, fontSize: 11))),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 8, color: Color(0xFF718096)), textAlign: TextAlign.center),
      ],
    );

    Widget condBtn(String label, String value, String current, ValueChanged<String> onChange) {
      final active = current == value;
      Color color;
      switch (value) {
        case 'OK':        color = green; break;
        case 'Defective': color = red;   break;
        default:          color = amber;
      }
      return GestureDetector(
        onTap: () => onChange(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.1) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? color : const Color(0xFFe2e8f0), width: 1.5)),
          child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            color: active ? color : const Color(0xFF718096))),
        ),
      );
    }

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
                decoration: BoxDecoration(color: red,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.download_outlined, color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Receive Items',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('${delivery['supplier']} · ${fmt(delivery['date'] as String?)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ])),
                  GestureDetector(onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              // Step indicator
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  step('1', 'Input Quantities', active: true),
                  const Expanded(child: Divider()),
                  step('2', 'Awaiting Check'),
                  const Expanded(child: Divider()),
                  step('3', 'Approved'),
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
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF90cdf4)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item['itemName'] as String? ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text('${item['itemNum']} · Expected: $expected ${item['uom'] ?? ''}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                        const SizedBox(height: 10),
                        TextField(
                          controller: qtyCtrlrs[i], keyboardType: TextInputType.number,
                          onChanged: (_) => setModal(() {}),
                          decoration: InputDecoration(
                            labelText: 'Actual Qty *', border: const OutlineInputBorder(), isDense: true,
                            suffixText: item['uom'] as String? ?? '')),
                        const SizedBox(height: 10),
                        const Text('Condition', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
                        const SizedBox(height: 6),
                        Row(children: [
                          condBtn('✅ OK',         'OK',        conditionList[i], (c) => setModal(() => conditionList[i] = c)),
                          const SizedBox(width: 6),
                          condBtn('❌ Defective',  'Defective', conditionList[i], (c) => setModal(() => conditionList[i] = c)),
                          const SizedBox(width: 6),
                          condBtn('⚠️ Shortage',  'Shortage',  conditionList[i], (c) => setModal(() => conditionList[i] = c)),
                        ]),
                        const SizedBox(height: 10),
                        TextField(controller: remarkCtrlrs[i],
                          decoration: const InputDecoration(
                            labelText: 'Remarks (optional)', border: OutlineInputBorder(), isDense: true,
                            hintText: 'e.g. 1 unit damaged packaging')),
                      ]),
                    );
                  }),
                  const SizedBox(height: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Received By (Your Name) *',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
                    const SizedBox(height: 4),
                    TextField(
                      controller: receivedByCtrl,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true,
                        hintText: 'Enter your full name')),
                  ]),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (receivedByCtrl.text.trim().isEmpty) return;
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
                          await FirebaseFirestore.instance.collection('deliveries')
                              .doc(delivery['id'] as String).update({
                            'items': updatedItems,
                            'receivedBy': receivedByCtrl.text.trim(),
                            'status': 'Awaiting Double Check',
                            'receivedAt': FieldValue.serverTimestamp(),
                          });
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Submitted for double check!'),
                              backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
                          }
                        } catch (err) {
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red));
                        }
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Submit for Double Check'),
                      style: ElevatedButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white),
                    )),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── View Stock Detail from scan (shows stock_inventory modal inline) ────────
  void _showStockDetailFromScan(Map<String, dynamic> masterItem) async {
    const red = Color(0xFFE8001C);
    final itemNum  = masterItem['num']  as String? ?? '';
    final itemName = masterItem['name'] as String? ?? '';

    // Look up in stock_inventory
    Map<String, dynamic>? stockItem;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('stock_inventory')
          .where('num', isEqualTo: itemNum)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data() as Map<String, dynamic>;
        final stock  = (d['stock']   as num?)?.toInt() ?? 0;
        final min    = (d['min']     as num?)?.toInt() ?? 0;
        final max    = (d['max']     as num?)?.toInt() ?? 0;
        stockItem = {
          'id':      snap.docs.first.id,
          'num':     d['num']     as String? ?? itemNum,
          'name':    d['name']    as String? ?? itemName,
          'group':   d['group']   as String? ?? '',
          'uom':     d['uom']     as String? ?? '',
          'stock':   stock,
          'min':     min,
          'max':     max,
          'reorder': (d['reorder'] as num?)?.toInt() ?? 0,
          'status':  stock > min ? (stock > max ? 'Over' : 'OK') : 'Low',
        };
      }
    } catch (e) {
      debugPrint('stock lookup error: $e');
    }

    if (!mounted) return;

    if (stockItem == null) {
      // No stock record found — show a simple info sheet
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.inventory_2_outlined, size: 40, color: Color(0xFFa0aec0)),
            const SizedBox(height: 12),
            Text(itemName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('No stock record found for "$itemNum".',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF718096))),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'))),
          ]),
        ),
      );
      return;
    }

    // Show the stock detail modal (mirrors _StaffInventoryState._showStockDetails)
    final item     = stockItem;
    final status   = item['status'] as String;
    final isLow    = status == 'Low';
    final isOver   = status == 'Over';
    final stock    = item['stock'] as int;
    final min      = item['min']   as int;
    final max      = item['max']   as int;
    final progress = max > 0 ? (stock / max).clamp(0.0, 1.0) : 0.0;
    final barColor = isLow ? Colors.orange : isOver ? Colors.purple : Colors.green;
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
                  color: red,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item['name'] as String,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(item['group'] as String,
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
                // Stock level bar
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isLow ? Colors.orange.shade50 : const Color(0xFFF0FFF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isLow ? Colors.orange.shade200 : const Color(0xFF9AE6B4))),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('$stock ${item['uom']}',
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
                // Detail rows
                _stockDetailRow('Item Number',    item['num']     as String),
                _stockDetailRow('Commodity Group', item['group']  as String),
                _stockDetailRow('UOM',             item['uom']    as String),
                _stockDetailRow('Reorder Qty',    '${item['reorder']} ${item['uom']}'),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stockDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 140, child: Text(label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
        Expanded(child: Text(value.isEmpty ? '—' : value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
      ]),
    );
  }

  // ── DASHBOARD ──
  Widget _buildDashboard() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('maintenance')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, maintSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('stock_inventory').snapshots(),
          builder: (context, stockSnap) {
            // Maintenance stats
            final maintDocs = maintSnap.data?.docs ?? [];
            final allServices = maintDocs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              return {
                ...data,
                'docId': d.id,
              };
            }).toList();

            // Filter all stats to only this staff member's services
            final myServices = _staffName.isEmpty
                ? allServices
                : allServices.where((s) {
                    final mechanic = (s['mechanic'] as String? ?? '').trim().toLowerCase();
                    return mechanic == _staffName.trim().toLowerCase();
                  }).toList();

            final ongoing = myServices.where((s) => s['status'] == 'Ongoing').length;
            final pending = myServices.where((s) => s['status'] == 'Pending').length;

            // Today's services — ALL services today (not filtered by mechanic)
            final now = DateTime.now();
            const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
            final todayFormatted = '${months[now.month - 1]} ${now.day}, ${now.year}';
            final todayServices = allServices.where((s) {
              final date = s['date'] as String? ?? '';
              return date == todayFormatted;
            }).toList();

            // Low stock count — matches StaffInventory: stock <= min is Low
            final stockDocs = stockSnap.data?.docs ?? [];
            final lowStock = stockDocs.where((d) {
              final data = d.data() as Map<String, dynamic>;
              final stock = (data['stock'] as num?)?.toInt() ?? 0;
              final min   = (data['min']   as num?)?.toInt() ?? 0;
              // Mirror StaffInventory logic: stock > min = OK, stock <= min = Low
              if (min > 0) return stock <= min;
              return (data['status'] as String? ?? '') == 'Low';
            }).length;

            final isLoading = maintSnap.connectionState == ConnectionState.waiting ||
                stockSnap.connectionState == ConnectionState.waiting;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GridView.count(
                  crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.4,
                  children: [
                    _statCard("Today's Services", isLoading ? '…' : '${todayServices.length}', Icons.today_outlined, _red),
                    _statCard('Ongoing', isLoading ? '…' : '$ongoing', Icons.autorenew, Colors.orange),
                    _statCard('Pending', isLoading ? '…' : '$pending', Icons.pending_outlined, const Color(0xFF718096)),
                    _statCard('Low Stock', isLoading ? '…' : '$lowStock', Icons.warning_amber_outlined, const Color(0xFF003087)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _sectionTitle("Today's Services"),
                  TextButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const StaffVehicleList())),
                    child: const Text('See all', style: TextStyle(fontSize: 12, color: Color(0xFF003087)))),
                ]),
                const SizedBox(height: 8),
                if (isLoading)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ))
                else if (todayServices.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
                    child: const Center(child: Text('No services for today.',
                      style: TextStyle(color: Color(0xFF718096), fontSize: 13))),
                  )
                else
                  ...todayServices.take(5).map((s) => _buildScheduleCard(s)),
              ]),
            );
          },
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 6),
        FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color))),
        Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF718096)), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> s) {
    final plate   = s['plate']  as String? ?? '—';
    final status  = s['status'] as String? ?? '—';
    final statusColor = status == 'Completed' ? Colors.green
        : status == 'Ongoing' ? Colors.orange
        : const Color(0xFF718096);

    // First service name from svcRows, fallback to desc
    final rows = s['svcRows'] as List?;
    String service = '—';
    if (rows != null && rows.isNotEmpty) {
      final n = rows.first['name'] as String? ?? '';
      if (n.isNotEmpty) service = n;
    }
    if (service == '—') service = s['desc'] as String? ?? '—';

    return GestureDetector(
      onTap: () => _showScheduleDetails(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(service, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(status, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  // ── Schedule card details modal (same as StaffMaintenance._showServiceDetails) ──
  void _showScheduleDetails(Map<String, dynamic> s) {
    Color statusColor(String st) {
      if (st == 'Completed') return Colors.green;
      if (st == 'Ongoing')   return Colors.orange;
      return const Color(0xFF718096);
    }

    String formatCost(String raw) {
      final clean = raw.replaceAll('₱', '').replaceAll(',', '').trim();
      final val = double.tryParse(clean);
      if (val == null) return raw.startsWith('₱') ? raw : '₱$raw';
      final parts = val.toStringAsFixed(2).split('.');
      final intPart = parts[0];
      final decPart = parts[1];
      if (intPart.length < 4) return '₱${val.toStringAsFixed(2)}';
      final buf = StringBuffer();
      for (int i = 0; i < intPart.length; i++) {
        if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
        buf.write(intPart[i]);
      }
      return '₱$buf.$decPart';
    }

    Widget detailRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
        Expanded(child: Text(value.isNotEmpty ? value : '-',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
      ]),
    );

    String formatNumber(double val) {
      final parts = val.toStringAsFixed(2).split('.');
      final intPart = parts[0];
      final decPart = parts[1];
      if (intPart.length < 4) return val.toStringAsFixed(2);
      final buf = StringBuffer();
      for (int i = 0; i < intPart.length; i++) {
        if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
        buf.write(intPart[i]);
      }
      return '$buf.$decPart';
    }

    Widget rowDetailCard(dynamic r, {required bool isService}) {
      final name     = r['name'] as String? ?? '';
      final qty      = r['qty']  as String? ?? '1';
      final uom      = r['uom']  as String? ?? '';
      final cost     = r['cost'] as String? ?? '0';
      final subtotal = (double.tryParse(cost) ?? 0) * (double.tryParse(qty) ?? 1);
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFe2e8f0)),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text('$qty $uom  •  $cost / unit',
              style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ])),
          Text(formatNumber(subtotal),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1a202c))),
        ]),
      );
    }

    final sc = statusColor(s['status'] as String? ?? '');

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => AnimatedPadding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          duration: const Duration(milliseconds: 150),
          child: SingleChildScrollView(
            child: Column(children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: const BoxDecoration(color: _red,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['plate'] as String? ?? '—',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(s['desc'] as String? ?? '',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ])),
                  GestureDetector(onTap: () => Navigator.pop(sheetCtx),
                    child: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              // Body
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  detailRow('Plate Number', s['plate'] as String? ?? ''),
                  detailRow('Mechanic',     s['mechanic'] as String? ?? ''),
                  detailRow('Service Date', s['date'] as String? ?? ''),
                  detailRow('Total Cost',   formatCost(s['cost'] as String? ?? '0')),
                  Row(children: [
                    const SizedBox(width: 130, child: Text('Status',
                      style: TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: sc.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text(s['status'] as String? ?? '',
                        style: TextStyle(fontSize: 12, color: sc, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  // Issues
                  if ((s['issues'] as List?)?.isNotEmpty == true) ...[
                    const Text('Vehicle Issues Reported',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4a5568))),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6,
                      children: (s['issues'] as List).map<Widget>((issue) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5F5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFED7D7), width: 1.5),
                        ),
                        child: Text(issue.toString(),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE8001C))),
                      )).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Services rendered
                  if ((s['svcRows'] as List?)?.isNotEmpty == true) ...[
                    const Text('Services Rendered',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4a5568))),
                    const SizedBox(height: 8),
                    ...(s['svcRows'] as List)
                        .where((r) => (r['name'] as String? ?? '').isNotEmpty)
                        .map((r) => rowDetailCard(r, isService: true)),
                    const SizedBox(height: 12),
                  ],
                  // Materials used
                  if ((s['matRows'] as List?)?.isNotEmpty == true) ...[
                    const Text('Materials Used',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4a5568))),
                    const SizedBox(height: 8),
                    ...(s['matRows'] as List)
                        .where((r) => (r['name'] as String? ?? '').isNotEmpty)
                        .map((r) => rowDetailCard(r, isService: false)),
                    const SizedBox(height: 12),
                  ],
                  // Pending notice
                  if (s['status'] == 'Pending')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline, color: Colors.orange, size: 16),
                        SizedBox(width: 8),
                        Expanded(child: Text('Waiting for admin approval.',
                          style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w500))),
                      ]),
                    ),
                  // Mark as Completed button (Ongoing only)
                  if (s['status'] == 'Ongoing') ...[
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Complete Service'),
                              content: Text('Mark service for ${s['plate']} as Completed?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Complete',
                                    style: TextStyle(color: Colors.green))),
                              ],
                            ),
                          );
                          if (confirm != true) return;

                          final docId = s['docId'] as String? ?? '';
                          if (docId.isEmpty) return;

                          // 1. Update status immediately
                          await FirebaseFirestore.instance
                              .collection('maintenance').doc(docId)
                              .update({'status': 'Completed'});

                          // 2. Close modal + show success right away
                          if (mounted) {
                            Navigator.pop(sheetCtx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: const Row(children: [
                                Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Text('Service marked as Completed!'),
                              ]),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ));
                          }

                          // 3. Run the rest in the background (non-blocking)
                          () async {
                          final uid  = FirebaseAuth.instance.currentUser?.uid ?? '';
                          final uDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                          final byName = (uDoc.data()?['name'] as String?) ?? 'Staff';
                          final now    = DateTime.now();
                          const _txnMonths = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                          final dateStr = '${_txnMonths[now.month - 1]} ${now.day}, ${now.year}';
                          final plate   = (s['plate'] as String? ?? '').trim().toUpperCase();

                          // Deduct stock + create issuances for materials
                          for (final r in (s['matRows'] as List<dynamic>? ?? [])) {
                            final name = r['name'] as String? ?? '';
                            final qty  = int.tryParse(r['qty']  as String? ?? '1') ?? 1;
                            final uom  = r['uom']  as String? ?? '';
                            final cost = double.tryParse(r['cost'] as String? ?? '0') ?? 0;
                            if (name.isEmpty || qty <= 0) continue;
                            final iSnap = await FirebaseFirestore.instance
                                .collection('item_master').where('name', isEqualTo: name).limit(1).get();
                            final iData = iSnap.docs.isNotEmpty
                                ? iSnap.docs.first.data() as Map<String, dynamic>
                                : <String, dynamic>{};
                            await FirebaseFirestore.instance.collection('issuances').add({
                              'id': 'ISS-AUTO-${DateTime.now().millisecondsSinceEpoch}',
                              'date': dateStr, 'plate': plate,
                              'assetDesc': s['desc'] ?? '', 'itemNum': iData['num'] ?? '',
                              'itemName': name, 'itemType': 'Material',
                              'commodityGroup': iData['group'] ?? '', 'uom': uom,
                              'qty': '$qty', 'unitCost': cost.toStringAsFixed(2),
                              'subtotal': (cost * qty).toStringAsFixed(2),
                              'createdBy': byName, 'maintenanceId': s['id'],
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                            final stockSnap = await FirebaseFirestore.instance
                                .collection('stock_inventory').where('name', isEqualTo: name).limit(1).get();
                            if (stockSnap.docs.isNotEmpty) {
                              final stockDoc    = stockSnap.docs.first;
                              final currentStock = (stockDoc['stock'] as num?)?.toInt() ?? 0;
                              final newStock     = (currentStock - qty).clamp(0, 99999);
                              final minLevel     = (stockDoc['min'] as num?)?.toInt() ?? 0;
                              await stockDoc.reference.update({
                                'stock': newStock,
                                'status': newStock >= minLevel ? 'OK' : 'Low',
                                'updatedAt': FieldValue.serverTimestamp(),
                              });
                            }
                            await FirebaseFirestore.instance.collection('transactions').add({
                              'item': name,
                              'desc': 'Issued for maintenance ${s['id']} - $plate',
                              'type': 'OUT', 'qty': '-$qty', 'date': dateStr, 'by': byName,
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                          }
                          // Issuances for service rows
                          for (final r in (s['svcRows'] as List<dynamic>? ?? [])) {
                            final name = r['name'] as String? ?? '';
                            final qty  = int.tryParse(r['qty']  as String? ?? '1') ?? 1;
                            final uom  = r['uom']  as String? ?? '';
                            final cost = double.tryParse(r['cost'] as String? ?? '0') ?? 0;
                            if (name.isEmpty) continue;
                            final iSnap = await FirebaseFirestore.instance
                                .collection('item_master').where('name', isEqualTo: name).limit(1).get();
                            final iData = iSnap.docs.isNotEmpty
                                ? iSnap.docs.first.data() as Map<String, dynamic>
                                : <String, dynamic>{};
                            await FirebaseFirestore.instance.collection('issuances').add({
                              'id': 'ISS-AUTO-${DateTime.now().millisecondsSinceEpoch}-S',
                              'date': dateStr, 'plate': plate,
                              'assetDesc': s['desc'] ?? '', 'itemNum': iData['num'] ?? '',
                              'itemName': name, 'itemType': 'Service',
                              'commodityGroup': iData['group'] ?? '', 'uom': uom,
                              'qty': '$qty', 'unitCost': cost.toStringAsFixed(2),
                              'subtotal': (cost * qty).toStringAsFixed(2),
                              'createdBy': byName, 'maintenanceId': s['id'],
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                          }
                          // Update vehicle status
                          final vSnap = await FirebaseFirestore.instance
                              .collection('vehicles').where('plate', isEqualTo: plate).limit(1).get();
                          if (vSnap.docs.isNotEmpty) {
                            await vSnap.docs.first.reference.update({
                              'status': 'Completed',
                              'completedAt': FieldValue.serverTimestamp(),
                              'lastSvcDate': '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}',
                            });
                          }
                          }(); // end background lambda
                        },
                        icon: const Icon(Icons.done_all, size: 16),
                        label: const Text('Mark as Completed'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green, foregroundColor: Colors.white),
                      )),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── INVENTORY ──
  Widget _buildInventory() {
    final items = [
      {'name': 'Engine Oil 10W-40', 'code': 'OIL-001', 'stock': 24, 'unit': 'L', 'low': false},
      {'name': 'Oil Filter', 'code': 'FLT-002', 'stock': 3, 'unit': 'pcs', 'low': true},
      {'name': 'Brake Pads', 'code': 'BRK-003', 'stock': 8, 'unit': 'set', 'low': false},
      {'name': 'Air Filter', 'code': 'FLT-004', 'stock': 2, 'unit': 'pcs', 'low': true},
      {'name': 'Coolant', 'code': 'CLT-005', 'stock': 15, 'unit': 'L', 'low': false},
    ];
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search parts...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true, fillColor: const Color(0xFFF7F8FA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _showReceiveModal(),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Receive'),
                style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final item = items[i];
              final isLow = item['low'] as bool;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: isLow ? Border.all(color: Colors.orange.shade200) : null,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(color: isLow ? Colors.orange.shade50 : const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.inventory_2_outlined, color: isLow ? Colors.orange : _red, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(item['code'] as String, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${item['stock']} ${item['unit']}', style: TextStyle(fontWeight: FontWeight.bold, color: isLow ? Colors.orange : const Color(0xFF1a202c))),
                        if (isLow) const Text('Low Stock', style: TextStyle(fontSize: 10, color: Colors.orange)),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showReceiveModal() {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('📥 Receive Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 12),
              const TextField(decoration: InputDecoration(labelText: 'Search Item', prefixIcon: Icon(Icons.search), border: OutlineInputBorder())),
              const SizedBox(height: 12),
              const TextField(decoration: InputDecoration(labelText: 'Quantity Received', prefixIcon: Icon(Icons.add_box_outlined), border: OutlineInputBorder()), keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('✅ Confirm', style: TextStyle(color: Colors.white)),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ── MAINTENANCE ──
  Widget _buildMaintenance() {
    final services = [
      {'id': 'SVC-001', 'plate': 'ABC-1234', 'vehicle': 'Isuzu Truck NQR', 'mechanic': 'Juan Dela Cruz', 'date': '2026-03-28', 'status': 'Ongoing', 'total': '₱2,500'},
      {'id': 'SVC-002', 'plate': 'XYZ-5678', 'vehicle': 'Toyota Hilux', 'mechanic': 'Pedro Santos', 'date': '2026-03-28', 'status': 'Pending', 'total': '₱1,800'},
      {'id': 'SVC-003', 'plate': 'DEF-9012', 'vehicle': 'Mitsubishi L300', 'mechanic': 'Jose Reyes', 'date': '2026-03-27', 'status': 'Completed', 'total': '₱3,200'},
    ];
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search services...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true, fillColor: const Color(0xFFF7F8FA),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              )),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _showNewServiceModal(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New'),
                style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: services.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final s = services[i];
              final statusColor = s['status'] == 'Completed' ? Colors.green : s['status'] == 'Ongoing' ? Colors.orange : const Color(0xFF718096);
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(s['id']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                        child: Text(s['status']!, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text('${s['plate']} • ${s['vehicle']}', style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568))),
                    Text('Mechanic: ${s['mechanic']}', style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(s['date']!, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                      Text(s['total']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1a202c))),
                    ]),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Service modal data (same as admin) ──
  static const _serviceItems = ['Oil Change Service'];
  static const _serviceItemData = {
    'Oil Change Service': {'uom': 'job', 'cost': '500'},
  };
  static const _itemMasterData = {
    'Engine Oil 10W-40': {'uom': 'L',   'cost': '450',  'barcode': '1234567890', 'qr': 'QR-ITM-001'},
    'Oil Filter':        {'uom': 'pcs', 'cost': '180',  'barcode': '0987654321', 'qr': 'QR-ITM-002'},
    'Brake Pads':        {'uom': 'set', 'cost': '1200', 'barcode': '1122334455', 'qr': 'QR-ITM-003'},
  };
  static const _vehicles = {
    'ABC-1234': {'desc': 'Isuzu Truck NQR 2021', 'owner': 'Juan Dela Cruz', 'type': 'Truck'},
    'XYZ-5678': {'desc': 'Toyota Hilux 2020', 'owner': 'Pedro Santos', 'type': 'Car'},
    'DEF-9012': {'desc': 'Mitsubishi L300 2019', 'owner': 'Jose Reyes', 'type': 'Truck'},
  };

  void _showNewServiceModal() {
    final plateCtrl = TextEditingController();
    final mechanicCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    Map<String, String>? foundVehicle;

    final List<Map<String, TextEditingController>> svcRows = [
      {'name': TextEditingController(), 'qty': TextEditingController(), 'uom': TextEditingController(), 'cost': TextEditingController()},
    ];
    final List<Map<String, TextEditingController>> matRows = [
      {'name': TextEditingController(), 'qty': TextEditingController(), 'uom': TextEditingController(), 'cost': TextEditingController()},
    ];

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          double totalCost() {
            double t = 0;
            for (final r in [...svcRows, ...matRows]) {
              t += (double.tryParse(r['cost']!.text) ?? 0) * (double.tryParse(r['qty']!.text) ?? 0);
            }
            return t;
          }

          return DraggableScrollableSheet(
            expand: false, initialChildSize: 0.92, maxChildSize: 0.97,
            builder: (_, ctrl) => SingleChildScrollView(
              controller: ctrl,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  decoration: const BoxDecoration(color: _red, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                  child: Row(children: [
                    Container(width: 44, height: 44,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.add, color: Colors.white, size: 22)),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('New Service', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                    GestureDetector(onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white)),
                  ]),
                ),
                Padding(
                  padding: EdgeInsets.only(left: 20, right: 20, top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Plate Number *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: plateCtrl,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (v) => setModal(() => foundVehicle = _vehicles[v.trim().toUpperCase()]),
                      decoration: InputDecoration(
                        hintText: 'Type plate number...',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF718096)),
                          tooltip: 'Scan Plate Number',
                          onPressed: () async {
                            final result = await Navigator.push<String>(context,
                              MaterialPageRoute(builder: (_) => const BarcodeScannerScreen(
                                title: 'Scan Plate Number',
                                hint: 'Point camera at the plate number',
                              )));
                            if (result != null) {
                              plateCtrl.text = result.toUpperCase();
                              setModal(() => foundVehicle = _vehicles[result.toUpperCase()]);
                            }
                          },
                        ),
                      ),
                    ),
                    if (foundVehicle != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFbee3f8))),
                        child: Row(children: [
                          const Icon(Icons.local_shipping_outlined, color: _red, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(foundVehicle!['desc']!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('${foundVehicle!['owner']} • ${foundVehicle!['type']}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                          ])),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(controller: mechanicCtrl,
                      decoration: const InputDecoration(labelText: 'Mechanic Name *', border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    TextField(controller: dateCtrl, readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Date Serviced *',
                        border: const OutlineInputBorder(),
                        hintText: 'Select date',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today_outlined, color: Color(0xFF718096)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx, initialDate: DateTime.now(),
                              firstDate: DateTime(2020), lastDate: DateTime(2030),
                              builder: (c, child) => Theme(
                                data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _red)),
                                child: child!),
                            );
                            if (picked != null) {
                              dateCtrl.text = '${_monthName(picked.month)} ${picked.day}, ${picked.year}';
                              setModal(() {});
                            }
                          },
                        ),
                      )),
                    const SizedBox(height: 16),
                    // Services Rendered
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Services Rendered', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4a5568))),
                      TextButton.icon(
                        onPressed: () => setModal(() => svcRows.add({'name': TextEditingController(), 'qty': TextEditingController(), 'uom': TextEditingController(), 'cost': TextEditingController()})),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Row', style: TextStyle(fontSize: 12)),
                      ),
                    ]),
                    ...svcRows.asMap().entries.map((e) => _svcItemRow(e.value, () => setModal(() => svcRows.removeAt(e.key)), setModal, ctx)),
                    const SizedBox(height: 12),
                    // Materials Used
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Materials Used', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4a5568))),
                      TextButton.icon(
                        onPressed: () => setModal(() => matRows.add({'name': TextEditingController(), 'qty': TextEditingController(), 'uom': TextEditingController(), 'cost': TextEditingController()})),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Row', style: TextStyle(fontSize: 12)),
                      ),
                    ]),
                    ...matRows.asMap().entries.map((e) => _matItemRow(e.value, () => setModal(() => matRows.removeAt(e.key)), setModal, ctx)),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Total Cost:', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2c5282), fontSize: 14)),
                      Text('₱${totalCost().toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2b6cb0))),
                    ]),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                      const SizedBox(width: 12),
                      Expanded(child: ElevatedButton(
                        onPressed: () {
                          if (plateCtrl.text.trim().isEmpty) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Service saved successfully'), backgroundColor: Colors.green));
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                        child: const Text('💾 Save'),
                      )),
                    ]),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _svcItemRow(Map<String, TextEditingController> row, VoidCallback onRemove, StateSetter setModal, BuildContext ctx) {
    final isFound = row['name']!.text.isNotEmpty;
    final currentVal = _serviceItems.contains(row['name']!.text) ? row['name']!.text : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            value: currentVal,
            hint: const Text('Select service...', style: TextStyle(fontSize: 11)),
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10), isDense: true),
            items: _serviceItems.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) {
              if (v != null) {
                row['name']!.text = v;
                final d = _serviceItemData[v];
                row['uom']!.text = d?['uom'] ?? 'job';
                row['cost']!.text = d?['cost'] ?? '0';
              }
              setModal(() {});
            },
          )),
          SizedBox(width: 32, child: IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), padding: EdgeInsets.zero, onPressed: onRemove)),
        ]),
        if (isFound) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFebf8ff), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF90cdf4))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.build_outlined, size: 16, color: Color(0xFF003087)),
                const SizedBox(width: 6),
                Expanded(child: Text(row['name']!.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
              ]),
              const SizedBox(height: 4),
              Text('UOM: ${row['uom']!.text}  •  Unit Cost: ₱${row['cost']!.text}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
              const SizedBox(height: 8),
              TextField(controller: row['qty'], keyboardType: TextInputType.number,
                onChanged: (_) => setModal(() {}),
                decoration: const InputDecoration(labelText: 'Quantity *', border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _matItemRow(Map<String, TextEditingController> row, VoidCallback onRemove, StateSetter setModal, BuildContext ctx) {
    final scanCtrl = TextEditingController();
    void lookup(String query) {
      final q = query.trim().toLowerCase();
      if (q.isEmpty) return;
      for (final entry in _itemMasterData.entries) {
        final d = entry.value;
        if (entry.key.toLowerCase().contains(q) || d['barcode'] == query.trim() || d['qr'] == query.trim()) {
          row['name']!.text = entry.key;
          row['uom']!.text = d['uom']!;
          row['cost']!.text = d['cost']!;
          setModal(() {});
          return;
        }
      }
      row['name']!.text = ''; row['uom']!.text = ''; row['cost']!.text = '';
      setModal(() {});
    }
    final isFound = row['name']!.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: TextField(
            controller: scanCtrl,
            decoration: InputDecoration(
              hintText: 'Scan or type item name / barcode...',
              hintStyle: const TextStyle(fontSize: 11),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              isDense: true,
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.search, size: 18, color: Color(0xFF718096)), padding: EdgeInsets.zero,
                  onPressed: () => lookup(scanCtrl.text)),
                IconButton(icon: const Icon(Icons.qr_code_scanner, size: 18, color: Color(0xFF003087)), padding: EdgeInsets.zero,
                  onPressed: () async {
                    final result = await Navigator.push<String>(ctx, MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
                    if (result != null) { scanCtrl.text = result; lookup(result); }
                  }),
              ]),
            ),
            onSubmitted: lookup,
          )),
          SizedBox(width: 32, child: IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), padding: EdgeInsets.zero, onPressed: onRemove)),
        ]),
        if (isFound) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFebf8ff), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF90cdf4))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFF003087)),
                const SizedBox(width: 6),
                Expanded(child: Text(row['name']!.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                GestureDetector(onTap: () { row['name']!.text = ''; row['uom']!.text = ''; row['cost']!.text = ''; scanCtrl.clear(); setModal(() {}); },
                  child: const Icon(Icons.close, size: 14, color: Color(0xFF718096))),
              ]),
              const SizedBox(height: 4),
              Text('UOM: ${row['uom']!.text}  •  Unit Cost: ₱${row['cost']!.text}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
              const SizedBox(height: 8),
              TextField(controller: row['qty'], keyboardType: TextInputType.number,
                onChanged: (_) => setModal(() {}),
                decoration: const InputDecoration(labelText: 'Quantity *', border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true)),
            ]),
          ),
        ] else if (scanCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 4),
          const Text('No item found for that code.', style: TextStyle(fontSize: 11, color: Colors.red)),
        ],
      ]),
    );
  }

  String _monthName(int m) => const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];

  // ── VEHICLES ──
  Widget _buildVehicles() {
    final vehicles = [
      {'plate': 'ABC-1234', 'desc': 'Isuzu Truck NQR 2021', 'type': 'truck', 'owner': 'Juan Dela Cruz', 'odo': '45,000 km'},
      {'plate': 'XYZ-5678', 'desc': 'Toyota Hilux 2020', 'type': 'car', 'owner': 'Pedro Santos', 'odo': '32,000 km'},
      {'plate': 'DEF-9012', 'desc': 'Mitsubishi L300 2019', 'type': 'truck', 'owner': 'Jose Reyes', 'odo': '78,000 km'},
    ];
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            Expanded(child: TextField(
              decoration: InputDecoration(
                hintText: 'Search vehicles...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true, fillColor: const Color(0xFFF7F8FA),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            )),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
              style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ]),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: vehicles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final v = vehicles[i];
              final isTruck = v['type'] == 'truck';
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(12)),
                    child: Icon(isTruck ? Icons.local_shipping_outlined : Icons.directions_car_outlined, color: _red, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v['plate']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(v['desc']!, style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568))),
                    Text('Owner: ${v['owner']}', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Icon(Icons.speed_outlined, size: 14, color: Color(0xFF718096)),
                    Text(v['odo']!, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                  ]),
                ]),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── NOTIFICATIONS ──
  Widget _buildNotifications() {
    final notifs = [
      {'title': 'Low Stock Alert', 'msg': 'Oil Filter is running low (3 pcs)', 'time': '2 hrs ago', 'icon': Icons.warning_amber_outlined, 'color': Colors.orange},
      {'title': 'Service Due', 'msg': 'ABC-1234 is due for service', 'time': '5 hrs ago', 'icon': Icons.build_outlined, 'color': _red},
      {'title': 'Stock Received', 'msg': 'Engine Oil 10W-40 restocked (+20L)', 'time': 'Yesterday', 'icon': Icons.check_circle_outline, 'color': Colors.green},
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: notifs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final n = notifs[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: (n['color'] as Color).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(n['icon'] as IconData, color: n['color'] as Color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(n['msg'] as String, style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
            ])),
            Text(n['time'] as String, style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
          ]),
        );
      },
    );
  }

  // ── PROFILE ──
  Widget _buildProfile() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const SizedBox(height: 12),
        CircleAvatar(radius: 40, backgroundColor: _red,
          child: const Text('ST', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
        const SizedBox(height: 12),
        const Text('Staff Member', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text('Service Staff', style: TextStyle(color: Color(0xFF718096))),
        const SizedBox(height: 20),
        _profileCard('Account Info', [
          _profileRow(Icons.person_outline, 'Full Name', 'Staff Member'),
          _profileRow(Icons.alternate_email, 'Email', 'staff@caltex.com'),
          _profileRow(Icons.badge_outlined, 'Role', 'Service Staff'),
        ]),
        const SizedBox(height: 12),
        _profileCard('Quick Stats', [
          _profileRow(Icons.build_outlined, 'Total Services', '12'),
          _profileRow(Icons.autorenew, 'Ongoing', '3'),
          _profileRow(Icons.warning_amber_outlined, 'Low Stock Items', '5'),
        ]),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pushAndRemoveUntil(context,
              MaterialPageRoute(builder: (_) => const _LogoutPlaceholder()), (_) => false),
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ]),
    );
  }

  Widget _profileCard(String title, List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1a202c))),
        const Divider(height: 20),
        ...rows,
      ]),
    );
  }

  Widget _profileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: _red),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ])),
      ]),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1a202c)));
  }
}

class _LogoutPlaceholder extends StatelessWidget {
  const _LogoutPlaceholder();
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

