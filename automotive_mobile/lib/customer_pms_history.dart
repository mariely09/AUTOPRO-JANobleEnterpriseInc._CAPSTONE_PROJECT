import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pms_history_details.dart';

/// Full-screen wrapper pushed via Navigator — no dashboard chrome.
/// AppBar: back button (left) + title + search icon (right).
class CustomerPmsScreen extends StatefulWidget {
  const CustomerPmsScreen({super.key});

  @override
  State<CustomerPmsScreen> createState() => _CustomerPmsScreenState();
}

class _CustomerPmsScreenState extends State<CustomerPmsScreen> {
  static const _red = Color(0xFFE8001C);
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  final _searchNotifier = ValueNotifier<String>('');

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF004B5F),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF004B5F), Color(0xFF006B7D), Color(0xFFEE152A)],
              stops: [0.0, 0.35, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: _searchOpen
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: Colors.white,
                onChanged: (v) => _searchNotifier.value = v,
                decoration: InputDecoration(
                  hintText: 'Search plate or description...',
                  hintStyle: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            _searchNotifier.value = '';
                          },
                          child: const Icon(
                            Icons.close,
                            color: Colors.white70,
                            size: 18,
                          ),
                        )
                      : null,
                ),
              )
            : const Text(
                'PMS History',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
        actions: [
          if (_searchOpen)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 20),
              onPressed: () {
                setState(() {
                  _searchOpen = false;
                });
                _searchCtrl.clear();
                _searchNotifier.value = '';
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white, size: 22),
              onPressed: () => setState(() => _searchOpen = true),
            ),
        ],
      ),
      body: _CustomerPmsBody(searchNotifier: _searchNotifier),
    );
  }
}

class CustomerPms extends StatefulWidget {
  const CustomerPms({super.key});

  @override
  State<CustomerPms> createState() => _CustomerPmsState();
}

class _CustomerPmsState extends State<CustomerPms> {
  static const _red = Color(0xFFE8001C);
  static const _bg = Color(0xFFF7F8FA);

  String _userName = '';
  String _companyName = '';

  // Search state lives here — NOT rebuilt by StreamBuilder
  final _searchCtrl = TextEditingController();
  final _searchNotifier = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadUserName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (mounted)
      setState(() {
        _userName = doc['name'] as String? ?? '';
        _companyName = doc.data()?['companyName'] as String? ?? '';
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_userName.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      color: _bg,
      child: Column(
        children: [
          // ── Header ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.history, color: _red, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'PMS History',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1a202c),
                    ),
                  ),
                ),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('vehicles')
                      .snapshots(),
                  builder: (_, snap) {
                    final uname = _userName.toLowerCase();
                    final cname = _companyName.toLowerCase();
                    final count = (snap.data?.docs ?? []).where((d) {
                      final owner = (d['owner'] as String? ?? '').toLowerCase();
                      return owner == uname ||
                          (cname.isNotEmpty && owner == cname);
                    }).length;
                    return Text(
                      '$count vehicle${count != 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF718096),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // ── Search bar — completely outside StreamBuilder ─────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => _searchNotifier.value = v,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1a202c)),
              decoration: InputDecoration(
                hintText: 'Search by plate or description...',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFa0aec0),
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: Color(0xFFa0aec0),
                ),
                suffixIcon: ValueListenableBuilder<String>(
                  valueListenable: _searchNotifier,
                  builder: (_, q, __) => q.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            _searchNotifier.value = '';
                          },
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Color(0xFFa0aec0),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFe2e8f0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFe2e8f0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _red, width: 1.5),
                ),
              ),
            ),
          ),

          // ── Vehicle list — rebuilt only by stream + search ────
          Expanded(child: _CustomerPmsBody(searchNotifier: _searchNotifier)),
        ],
      ),
    );
  }
}

// ── Vehicle card ─────────────────────────────────────────────
class _VehicleHistoryCard extends StatelessWidget {
  final String plate;
  final String desc;
  final String type;
  static const _red = Color(0xFFE8001C);

  const _VehicleHistoryCard({
    required this.plate,
    required this.desc,
    required this.type,
  });

  IconData get _vehicleIcon {
    final t = type.toLowerCase();
    if (t.contains('truck')) return Icons.local_shipping_outlined;
    return Icons.directions_car_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('maintenance')
          .where('plate', isEqualTo: plate)
          .where('status', isEqualTo: 'Completed')
          .snapshots(),
      builder: (context, snap) {
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

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  PmsHistoryDetails(plate: plate, desc: desc, type: type),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plate,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF1a202c),
                        ),
                      ),
                      Text(
                        desc,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF718096),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.receipt_long_outlined,
                            size: 12,
                            color: Color(0xFF718096),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${docs.length} service record${docs.length != 1 ? 's' : ''}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF718096),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₱${totalCost.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1a202c),
                      ),
                    ),
                    const Text(
                      'total spent',
                      style: TextStyle(fontSize: 9, color: Color(0xFF718096)),
                    ),
                    const SizedBox(height: 6),
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF718096),
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Shared body widget — used by both CustomerPms and CustomerPmsScreen ──────
class _CustomerPmsBody extends StatefulWidget {
  final ValueNotifier<String> searchNotifier;
  const _CustomerPmsBody({required this.searchNotifier});

  @override
  State<_CustomerPmsBody> createState() => _CustomerPmsBodyState();
}

class _CustomerPmsBodyState extends State<_CustomerPmsBody> {
  String _userName = '';
  String _companyName = '';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (mounted)
      setState(() {
        _userName = doc['name'] as String? ?? '';
        _companyName = doc.data()?['companyName'] as String? ?? '';
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_userName.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('vehicles').snapshots(),
      builder: (context, vSnap) {
        if (vSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final uname = _userName.toLowerCase();
        final cname = _companyName.toLowerCase();
        final allVehicles = (vSnap.data?.docs ?? []).where((d) {
          final owner = (d['owner'] as String? ?? '').toLowerCase();
          return owner == uname || (cname.isNotEmpty && owner == cname);
        }).toList();

        return ValueListenableBuilder<String>(
          valueListenable: widget.searchNotifier,
          builder: (_, q, __) {
            final query = q.toLowerCase().trim();
            final filtered = query.isEmpty
                ? allVehicles
                : allVehicles.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final plate = (data['plate'] as String? ?? '')
                        .toLowerCase();
                    final desc = (data['desc'] as String? ?? '').toLowerCase();
                    return plate.contains(query) || desc.contains(query);
                  }).toList();

            if (filtered.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    query.isNotEmpty
                        ? 'No vehicles match "$q".'
                        : 'No vehicles registered under your name.',
                    style: const TextStyle(color: Color(0xFF718096)),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) {
                final vData = filtered[i].data() as Map<String, dynamic>;
                return _VehicleHistoryCard(
                  plate: vData['plate'] as String? ?? '',
                  desc: vData['desc'] as String? ?? '',
                  type: vData['type'] as String? ?? '',
                );
              },
            );
          },
        );
      },
    );
  }
}
