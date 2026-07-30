import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminIssuances extends StatelessWidget {
  const AdminIssuances({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF7F8FA),
      body: AdminIssuancesBody(),
    );
  }
}

/// Embeddable body — can be placed inside any parent (e.g. a tab in the dashboard).
class AdminIssuancesBody extends StatefulWidget {
  final String searchQuery;
  const AdminIssuancesBody({super.key, this.searchQuery = ''});

  @override
  State<AdminIssuancesBody> createState() => _AdminIssuancesBodyState();
}

class _AdminIssuancesBodyState extends State<AdminIssuancesBody> {
  static const _red = Color(0xFFE8001C);

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _typeFilter = 'all'; // 'all', 'Material', 'Service'

  // Live vehicle lookup (plate -> desc)
  Map<String, String> _vehicleDescMap = {};

  static const _monthsShort = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  static const _monthsLong  = ['January','February','March','April','May','June','July','August','September','October','November','December'];

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    final snap = await FirebaseFirestore.instance.collection('vehicles').get();
    if (!mounted) return;
    setState(() {
      _vehicleDescMap = {};
      for (final d in snap.docs) {
        final data = d.data();
        final plate = data['plate'] as String? ?? '';
        final desc = data['desc'] as String? ?? data['assetDescription'] as String? ?? '';
        if (plate.isNotEmpty) _vehicleDescMap[plate] = desc;
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(String dateStr) {
    if (dateStr.isEmpty || dateStr == '—') return dateStr;
    for (int i = 0; i < _monthsShort.length; i++) {
      if (dateStr.startsWith(_monthsShort[i])) {
        return dateStr.replaceFirst(_monthsShort[i], _monthsLong[i]);
      }
    }
    final slash = dateStr.split('/');
    if (slash.length == 3) {
      final m = int.tryParse(slash[0]);
      final d = int.tryParse(slash[1]);
      final y = int.tryParse(slash[2]);
      if (m != null && d != null && y != null && m >= 1 && m <= 12) {
        return '${_monthsLong[m - 1]} $d, $y';
      }
    }
    final dt = DateTime.tryParse(dateStr);
    if (dt != null) return '${_monthsLong[dt.month - 1]} ${dt.day}, ${dt.year}';
    return dateStr;
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('issuances')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        final all = docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          return {...data, 'docId': d.id};
        }).toList();

        final afterType = _typeFilter == 'all'
            ? all
            : all.where((d) => (d['itemType'] as String? ?? '') == _typeFilter).toList();

        final activeQuery = widget.searchQuery.isNotEmpty ? widget.searchQuery : _searchQuery;
        final filtered = activeQuery.isEmpty
            ? afterType
            : afterType.where((d) {
                final name  = (d['itemName'] ?? d['item'] ?? '').toString().toLowerCase();
                final plate = (d['plate']     as String? ?? '').toLowerCase();
                final by    = (d['createdBy'] as String? ?? '').toLowerCase();
                return name.contains(activeQuery) ||
                    plate.contains(activeQuery) ||
                    by.contains(activeQuery);
              }).toList();

        final totalMat = all.where((d) => (d['itemType'] as String? ?? '') == 'Material').length;
        final totalSvc = all.where((d) => (d['itemType'] as String? ?? '') == 'Service').length;

        return Column(children: [
          // ── Stat chips ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              _chip('All',      '${all.length}', const Color(0xFF003087), Icons.list_alt_outlined,    'all'),
              const SizedBox(width: 8),
              _chip('Material', '$totalMat',     _red,                    Icons.inventory_2_outlined, 'Material'),
              const SizedBox(width: 8),
              _chip('Service',  '$totalSvc',     const Color(0xFF003087), Icons.build_outlined,       'Service'),
            ]),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No issuances found.', style: TextStyle(color: Color(0xFF718096))))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _issCard(filtered[i]),
                  ),
          ),
        ]);
      },
    );
  }

  Widget _chip(String label, String value, Color color, IconData icon, String filter) {
    final isActive = _typeFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _typeFilter = filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isActive ? color : Colors.transparent, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
          ),
          child: Column(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF718096))),
          ]),
        ),
      ),
    );
  }

  Widget _issCard(Map<String, dynamic> iss) {
    final name     = (iss['itemName'] ?? iss['item'] ?? '—') as String;
    final plate    = iss['plate']      as String? ?? '—';
    final date     = iss['date']       as String? ?? '—';
    final qty      = iss['qty']?.toString() ?? '—';
    final uom      = iss['uom']        as String? ?? '';
    final subtotal = double.tryParse(iss['subtotal']?.toString() ?? '0') ?? 0;
    final group    = iss['commodityGroup'] as String? ?? '';
    final isMat    = (iss['itemType']  as String? ?? '') == 'Material';
    final typeColor = isMat ? _red : const Color(0xFF003087);
    final typeBg    = isMat ? const Color(0xFFFFF5F5) : const Color(0xFFebf8ff);
    // Look up vehicle description from live vehicles data
    final liveDesc  = _vehicleDescMap[plate] ?? '';

    return GestureDetector(
      onTap: () => _showDetail(iss),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plate ?? '—', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (liveDesc.isNotEmpty)
              Text(liveDesc, style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
            Text(
              name,
              style: const TextStyle(fontSize: 11, color: Color(0xFF4a5568)),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: typeBg, borderRadius: BorderRadius.circular(20)),
                child: Text(isMat ? 'Material' : 'Service',
                  style: TextStyle(fontSize: 9, color: typeColor, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Text(_fmtDate(date), style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₱${subtotal.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1a202c))),
            Text('$qty $uom', style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
          ]),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFa0aec0)),
        ]),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> iss) {
    final name      = (iss['itemName'] ?? iss['item'] ?? '—') as String;
    final itemNum   = iss['itemNum']       as String? ?? '—';
    final plate     = iss['plate']         as String? ?? '—';
    // Look up vehicle description from live vehicles data (stays in sync with edits)
    final assetDesc = _vehicleDescMap[plate] ?? (iss['assetDesc'] as String? ?? '');
    final date      = iss['date']          as String? ?? '—';
    final qty       = iss['qty']?.toString() ?? '0';
    final uom       = iss['uom']           as String? ?? '';
    final unitCost  = double.tryParse(iss['unitCost']?.toString() ?? '0') ?? 0;
    final subtotal  = double.tryParse(iss['subtotal']?.toString() ?? '0') ?? 0;
    final by        = iss['createdBy']     as String? ?? '—';
    final group     = iss['commodityGroup'] as String? ?? '—';
    final isMat     = (iss['itemType']     as String? ?? '') == 'Material';
    final color     = isMat ? _red : const Color(0xFF003087);

    Widget detailRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
        Expanded(child: Text(value.isNotEmpty && value != '—' ? value : '—',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
      ]),
    );

    Widget costBox(String label, String value, String sub, Color bg, Color valueColor) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF718096), fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: valueColor),
            textAlign: TextAlign.center),
          if (sub.isNotEmpty)
            Text(sub, style: const TextStyle(fontSize: 9, color: Color(0xFF718096))),
        ]),
      );

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.75, maxChildSize: 0.92,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            // ── Colored header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(plate, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  if (assetDesc.isNotEmpty)
                    Text(assetDesc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
                GestureDetector(onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                // ── Subtotal + date summary banner ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFe2e8f0))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Issued By', style: TextStyle(color: Color(0xFF718096), fontSize: 10, fontWeight: FontWeight.w700)),
                      Text(by,
                        style: const TextStyle(color: Color(0xFF1a202c), fontSize: 16, fontWeight: FontWeight.w800)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('Date', style: TextStyle(color: Color(0xFF718096), fontSize: 10, fontWeight: FontWeight.w700)),
                      Text(_fmtDate(date),
                        style: const TextStyle(color: Color(0xFF1a202c), fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),
                // ── Item details ──
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFe2e8f0))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('📋  ITEM DETAILS',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF718096), letterSpacing: 0.5)),
                    const SizedBox(height: 12),
                    detailRow('Item Name',       name),
                    detailRow('Item Type',       isMat ? 'Material' : 'Service'),
                    detailRow('Commodity Group', group),
                    detailRow('UOM',             uom),
                  ]),
                ),
                const SizedBox(height: 12),
                // ── Cost breakdown ──
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFe2e8f0))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('💰  COST BREAKDOWN',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF718096), letterSpacing: 0.5)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: costBox('Quantity',  qty,   uom,  const Color(0xFFF7F8FA), const Color(0xFF1a202c))),
                      const SizedBox(width: 8),
                      Expanded(child: costBox('Unit Cost', '₱${unitCost.toStringAsFixed(2)}', '', const Color(0xFFebf8ff), const Color(0xFF2b6cb0))),
                      const SizedBox(width: 8),
                      Expanded(child: costBox('Subtotal',  '₱${subtotal.toStringAsFixed(2)}', '', const Color(0xFFFFF5F5), _red)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}