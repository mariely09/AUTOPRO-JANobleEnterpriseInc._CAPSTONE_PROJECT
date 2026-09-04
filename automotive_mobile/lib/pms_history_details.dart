import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PmsHistoryDetails extends StatelessWidget {
  final String plate;
  final String desc;
  final String type;

  static const _red = Color(0xFFE8001C);
  static const _bg = Color(0xFFF7F8FA);

  const PmsHistoryDetails({super.key, required this.plate, required this.desc, required this.type});

  IconData get _vehicleIcon {
    final t = type.toLowerCase();
    if (t.contains('car')) return Icons.directions_car_outlined;
    if (t.contains('truck')) return Icons.local_shipping_outlined;
    return Icons.directions_car_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('maintenance')
            .where('plate', isEqualTo: plate)
            .where('status', isEqualTo: 'Completed')
            .snapshots(),
        builder: (context, snap) {
          // Show a full-screen centered spinner while data is loading
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = (snap.data?.docs ?? [])
            ..sort((a, b) {
              final aTime = (a.data() as Map)['createdAt'];
              final bTime = (b.data() as Map)['createdAt'];
              if (aTime == null || bTime == null) return 0;
              return (bTime as Timestamp).compareTo(aTime as Timestamp);
            });

          final totalCost = docs.fold<double>(0, (sum, d) {
            final cost = (d['cost'] as String? ?? '0')
                .replaceAll('₱', '')
                .replaceAll(',', '');
            return sum + (double.tryParse(cost) ?? 0);
          });

          return CustomScrollView(
            slivers: [
              // ── App Bar ──
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                backgroundColor: const Color(0xFF004B5F),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                title: _CollapsedTitle(plate: plate),
                flexibleSpace: FlexibleSpaceBar(
                  background: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('vehicles')
                        .where('plate', isEqualTo: plate)
                        .limit(1)
                        .snapshots(),
                    builder: (context, vSnap) {
                      final vData = vSnap.data?.docs.isNotEmpty == true
                          ? vSnap.data!.docs.first.data() as Map<String, dynamic>
                          : <String, dynamic>{};
                      final lastSvcOdo = vData['lastSvcOdo']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
                      final showOdo = lastSvcOdo.isNotEmpty && lastSvcOdo != '0';
                      return Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF004B5F), Color(0xFFEE152A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: SafeArea(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 44),
                              Text(plate,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1)),
                              const SizedBox(height: 4),
                              Text(desc,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                              const SizedBox(height: 16),
                              // ── Stats row inside the header ──
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(children: [
                                  Expanded(child: _headerStat(
                                    Icons.receipt_long_outlined,
                                    '${docs.length}',
                                    'Service${docs.length != 1 ? 's' : ''}',
                                  )),
                                  const SizedBox(width: 8),
                                  Expanded(child: _headerStat(
                                    Icons.payments_outlined,
                                    '₱${totalCost.toStringAsFixed(2)}',
                                    'Total Spent',
                                  )),
                                  if (showOdo) ...[
                                    const SizedBox(width: 8),
                                    Expanded(child: _headerStat(
                                      Icons.speed_outlined,
                                      '${int.tryParse(lastSvcOdo) ?? lastSvcOdo} km',
                                      'Last Svc Odo',
                                    )),
                                  ],
                                ]),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── Section header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(children: [
                    const Icon(Icons.history, color: _red, size: 16),
                    const SizedBox(width: 6),
                    const Text('Service Records',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1a202c))),
                  ]),
                ),
              ),

              // ── Records list ──
              docs.isEmpty
                  ? const SliverFillRemaining(
                      child: Center(
                        child: Text('No completed services yet.',
                            style: TextStyle(color: Color(0xFF718096))),
                      ),
                    )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _ServiceRecordCard(
                                      data: docs[i].data()
                                          as Map<String, dynamic>),
                                );
                              },
                              childCount: docs.length,
                            ),
                          ),
                        ),
            ],
          );
        },
      ),
    );
  }

  // Header stat — white translucent, matches website phd-stat-item style
  Widget _headerStat(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: Colors.white.withOpacity(0.85), size: 14),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              maxLines: 1,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 9, color: Colors.white.withOpacity(0.65))),
      ]),
    );
  }
}

// ── Individual service record card ──────────────────────────────────────────
class _ServiceRecordCard extends StatelessWidget {
  final Map<String, dynamic> data;
  static const _red = Color(0xFFE8001C);

  const _ServiceRecordCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cost = data['cost'] as String? ?? '—';
    final mechanic = data['mechanic'] as String? ?? '—';
    final date = data['date'] as String? ?? '—';
    final odometer = data['odometer'];
    final odoStr = odometer != null && odometer.toString().replaceAll(RegExp(r'[^0-9]'), '') != '0' && odometer.toString().isNotEmpty
        ? '${odometer} km'
        : null;

    return GestureDetector(
      onTap: () => _showDetails(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: Offset(0, 4))],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(date, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1a202c))),
            Text(mechanic, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
            if (odoStr != null)
              Text(odoStr, style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(cost, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1a202c))),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: const Text('Completed', style: TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFa0aec0)),
        ]),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final svcRows = (data['svcRows'] as List<dynamic>? ?? [])
        .where((x) => (x['name'] as String? ?? '').isNotEmpty)
        .toList();
    final matRows = (data['matRows'] as List<dynamic>? ?? [])
        .where((x) => (x['name'] as String? ?? '').isNotEmpty)
        .toList();
    final issues = (data['issues'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.65, maxChildSize: 0.9,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: const BoxDecoration(
                color: _red,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(data['date'] as String? ?? '—', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(data['mechanic'] as String? ?? '—', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
                GestureDetector(onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _detailRow('Service Date', data['date'] as String? ?? '—'),
                _detailRow('Mechanic', data['mechanic'] as String? ?? '—'),
                _detailRow('Odometer', () {
                  final odo = data['odometer'];
                  if (odo == null) return '—';
                  final digits = odo.toString().replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits.isEmpty || digits == '0') return '—';
                  return '$odo km';
                }()),
                _detailRow('Total Cost', data['cost'] as String? ?? '—'),
                Row(children: [
                  const SizedBox(width: 110, child: Text('Status', style: TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                    child: const Text('Completed', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                  ),
                ]),
                // Issues
                if (issues.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Vehicle Issues Reported', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4a5568))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: issues.map((issue) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5F5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFED7D7), width: 1.5),
                      ),
                      child: Text(issue, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE8001C))),
                    )).toList(),
                  ),
                ],
                // Services Rendered
                if (svcRows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Services Rendered', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2b6cb0))),
                  const SizedBox(height: 8),
                  ...svcRows.map((s) => _itemRow(s as Map<String, dynamic>, const Color(0xFF2b6cb0))),
                ],
                // Materials Used
                if (matRows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Materials Used', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0d9488))),
                  const SizedBox(height: 8),
                  ...matRows.map((m) => _itemRow(m as Map<String, dynamic>, const Color(0xFF0d9488))),
                ],
                const SizedBox(height: 16),
                const Divider(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF4a5568))),
                  Text(data['cost'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1a202c))),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
        Expanded(child: Text(value.isNotEmpty ? value : '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
      ]),
    );
  }

  Widget _itemRow(Map<String, dynamic> item, Color color) {
    final unitCost = double.tryParse((item['cost'] as String? ?? '0').replaceAll('₱', '')) ?? 0;
    final qty = double.tryParse(item['qty'] as String? ?? '1') ?? 1;
    final subtotal = unitCost * qty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF1a202c)),
              children: [
                TextSpan(text: item['name'] as String? ?? ''),
                if ((item['uom'] as String? ?? '').isNotEmpty)
                  TextSpan(
                    text: ' (${item['uom']})',
                    style: const TextStyle(fontWeight: FontWeight.w400, color: Color(0xFF718096)),
                  ),
              ],
            ),
          ),
          Text('${item['qty']}  •  ₱${unitCost.toStringAsFixed(2)} / unit', style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
        ])),
        Text('₱${subtotal.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
      ]),
    );
  }
}

// ── Collapsed title — fades in only when the SliverAppBar is scrolled up ──
class _CollapsedTitle extends StatelessWidget {
  final String plate;
  const _CollapsedTitle({required this.plate});

  @override
  Widget build(BuildContext context) {
    // FlexibleSpaceBar collapses when scroll offset reaches expandedHeight - kToolbarHeight.
    // We read the FlexibleSpaceBar's collapse ratio via the ancestor ScrollView.
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final double opacity = settings == null
        ? 1.0
        : (1.0 -
                ((settings.currentExtent - settings.minExtent) /
                    (settings.maxExtent - settings.minExtent)))
            .clamp(0.0, 1.0);

    return Opacity(
      opacity: opacity,
      child: Text(
        plate,
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}
