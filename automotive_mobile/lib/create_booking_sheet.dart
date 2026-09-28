import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CreateBookingSheet — mirrors the website "Add New Booking" modal
//
// Steps:
//   1. Customer search (name / email)
//   2. Vehicle picker (from customer's vehicles collection)
//   3. Services multi-select (item_master where type=service)
//   4. Date picker  (inline calendar; past + full slots greyed)
//   5. Time slot    (8 fixed slots; booked ones disabled)
//   +  Notes (optional)
//
// Saves to service_bookings with status:'Approved', bookedBy: widget.bookedBy
// Sends in-app notification to customer on success.
// ═══════════════════════════════════════════════════════════════════════════

class CreateBookingSheet extends StatefulWidget {
  /// 'admin' or 'staff'
  final String bookedBy;
  const CreateBookingSheet({super.key, this.bookedBy = 'admin'});

  @override
  State<CreateBookingSheet> createState() => _CreateBookingSheetState();
}

class _CreateBookingSheetState extends State<CreateBookingSheet> {
  static const _red   = Color(0xFFE8001C);
  static const _green = Color(0xFF38a169);

  static const _allSlots = [
    '8:00 AM', '9:00 AM', '10:00 AM', '11:00 AM',
    '1:00 PM', '2:00 PM', '3:00 PM',  '4:00 PM',
  ];
  static const _arriveBy = {
    '8:00 AM': '7:45 AM', '9:00 AM': '8:45 AM',
    '10:00 AM': '9:45 AM', '11:00 AM': '10:45 AM',
    '1:00 PM': '12:45 PM', '2:00 PM': '1:45 PM',
    '3:00 PM': '2:45 PM',  '4:00 PM': '3:45 PM',
  };
  static const _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];
  static const _shortM = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  // ── State ────────────────────────────────────────────────────────────────
  final _searchCtrl  = TextEditingController();
  final _notesCtrl   = TextEditingController();
  final _svcSrchCtrl = TextEditingController();

  List<Map<String, dynamic>> _allCustomers = [];
  Map<String, dynamic>? _selectedCustomer;

  List<Map<String, dynamic>> _vehicles        = [];
  Map<String, dynamic>?      _selectedVehicle;
  bool                       _loadingVehicles = false;

  List<Map<String, dynamic>> _allServices      = [];
  Map<String, bool>          _selectedServices = {};
  bool                       _loadingServices  = true;

  late int _calYear;
  late int _calMonth;
  String                     _selectedDate  = '';
  String                     _selectedTime  = '';
  Map<String, List<String>>  _bookedSlots   = {};
  bool                       _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calYear  = now.year;
    _calMonth = now.month;
    _loadCustomers();
    _loadServices();
    _loadBookedSlots();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _notesCtrl.dispose();
    _svcSrchCtrl.dispose();
    super.dispose();
  }

  // ── Loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadCustomers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'customer')
          .get();
      if (!mounted) return;
      setState(() {
        _allCustomers = snap.docs
            .map((d) => {...d.data(), 'uid': d.id})
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _loadServices() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('item_master')
          .get();
      if (!mounted) return;
      setState(() {
        _allServices = snap.docs
            .map((d) => {...d.data(), 'id': d.id})
            .where((d) {
              final t = (d['type']     as String? ?? '').toLowerCase();
              final u = (d['itemType'] as String? ?? '').toLowerCase();
              return t == 'service' || u == 'service';
            })
            .toList();
        _loadingServices = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingServices = false);
    }
  }

  Future<void> _loadBookedSlots() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('service_bookings')
          .where('status', isEqualTo: 'Approved')
          .get();
      final map = <String, List<String>>{};
      for (final d in snap.docs) {
        final date = d.data()['preferredDate'] as String? ?? '';
        final time = d.data()['preferredTime'] as String? ?? '';
        if (date.isNotEmpty && time.isNotEmpty) {
          map.putIfAbsent(date, () => []);
          if (!map[date]!.contains(time)) map[date]!.add(time);
        }
      }
      if (!mounted) return;
      setState(() { _bookedSlots = map; });
    } catch (_) {
      // non-fatal — calendar will just show without slot data
    }
  }

  Future<void> _loadVehicles(String uid) async {
    setState(() { _vehicles = []; _selectedVehicle = null; _loadingVehicles = true; });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('ownerId', isEqualTo: uid)
          .get();
      if (!mounted) return;
      setState(() {
        _vehicles        = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
        _loadingVehicles = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingVehicles = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool get _canSubmit =>
      _selectedCustomer != null &&
      _selectedVehicle  != null &&
      _selectedServices.isNotEmpty &&
      _selectedDate.isNotEmpty &&
      _selectedTime.isNotEmpty;

  String _fmtLong(String s) {
    final p = s.split('-');
    if (p.length != 3) return s;
    final m = int.tryParse(p[1]) ?? 1;
    return '${_months[m - 1]} ${int.tryParse(p[2]) ?? p[2]}, ${p[0]}';
  }

  String _fmtShort(String s) {
    final p = s.split('-');
    if (p.length != 3) return s;
    final m = int.tryParse(p[1]) ?? 1;
    return '${_shortM[m - 1]} ${int.tryParse(p[2]) ?? p[2]}, ${p[0]}';
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_canSubmit || _saving) return;
    setState(() => _saving = true);

    final db = FirebaseFirestore.instance;
    final svcIds = _selectedServices.keys.toList();
    final svcNames = svcIds.map((id) {
      final s = _allServices.firstWhere((s) => s['id'] == id,
          orElse: () => <String, dynamic>{'name': id});
      return s['name'] as String? ?? id;
    }).toList();

    final data = <String, dynamic>{
      'customerId':    _selectedCustomer!['uid'],
      'customerName':  _selectedCustomer!['name']  ?? '',
      'customerEmail': _selectedCustomer!['email'] ?? '',
      'vehicleId':     _selectedVehicle!['id'],
      'plate':         _selectedVehicle!['plate']  ?? '',
      'make':          _selectedVehicle!['make']   ?? '',
      'model':         _selectedVehicle!['model']  ?? '',
      'year':          _selectedVehicle!['year']   ?? '',
      'services':      svcNames,
      'serviceIds':    svcIds,
      'preferredDate': _selectedDate,
      'preferredTime': _selectedTime,
      'notes':         _notesCtrl.text.trim(),
      'status':        'Approved',
      'bookedBy':      widget.bookedBy,
      'createdAt':     FieldValue.serverTimestamp(),
    };

    try {
      await db.collection('service_bookings').add(data);

      final custId = _selectedCustomer!['uid'] as String? ?? '';
      if (custId.isNotEmpty) {
        db.collection('notifications').add({
          'title':      '📅 Service Booking Confirmed',
          'message':    'Your service booking for ${data['plate']} on '
              '${_fmtShort(_selectedDate)} at $_selectedTime has been confirmed.',
          'type':       'success',
          'targetRole': '',
          'targetUid':  custId,
          'createdAt':  FieldValue.serverTimestamp(),
          'readBy':     <String, bool>{},
          'isRead':     false,
        });
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Booking created successfully!'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        maxChildSize: 0.97,
        builder: (_, ctrl) => Column(children: [
          _header(),
          Expanded(
            child: SingleChildScrollView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _step1Customer(),
                  if (_selectedCustomer != null) ...[
                    const SizedBox(height: 20),
                    _step2Vehicle(),
                  ],
                  if (_selectedVehicle != null) ...[
                    const SizedBox(height: 20),
                    _step3Services(),
                    const SizedBox(height: 20),
                    _step4Calendar(),
                    if (_selectedDate.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _step5Time(),
                    ],
                    const SizedBox(height: 20),
                    _notes(),
                    const SizedBox(height: 16),
                    _summary(),
                    const SizedBox(height: 16),
                    _submitBtn(),
                  ],
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
          colors: [_red, Color(0xFFb5001a)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: Row(children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
            color: Colors.white24, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.calendar_month_outlined,
            color: Colors.white, size: 20),
      ),
      const SizedBox(width: 12),
      const Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add New Booking', style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          Text('Create a service booking for a customer',
              style: TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      )),
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
              color: Colors.white24, shape: BoxShape.circle),
          child: const Icon(Icons.close, color: Colors.white, size: 16),
        ),
      ),
    ]),
  );

  Widget _lbl(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700,
        color: Color(0xFF4a5568), letterSpacing: 0.4)),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1 — CUSTOMER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _step1Customer() {
    if (_selectedCustomer != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _lbl('1. CUSTOMER'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF5F5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFfeb2b2)),
          ),
          child: Row(children: [
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_selectedCustomer!['name'] as String? ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 13, color: Color(0xFF1a202c))),
              const SizedBox(height: 2),
              Text(_selectedCustomer!['email'] as String? ?? '',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
            ])),
            GestureDetector(
              onTap: () => setState(() {
                _selectedCustomer = null;
                _selectedVehicle  = null;
                _vehicles         = [];
                _searchCtrl.clear();
              }),
              child: const Icon(Icons.close, size: 18, color: Color(0xFF718096)),
            ),
          ]),
        ),
      ]);
    }

    final q       = _searchCtrl.text.toLowerCase();
    final results = q.isEmpty
        ? <Map<String, dynamic>>[]
        : _allCustomers
            .where((c) =>
                (c['name']  as String? ?? '').toLowerCase().contains(q) ||
                (c['email'] as String? ?? '').toLowerCase().contains(q))
            .take(8)
            .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lbl('1. CUSTOMER'),
      TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search customer name or email…',
          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFFa0aec0)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _red)),
          filled: true, fillColor: const Color(0xFFF8FAFC),
        ),
        onChanged: (_) => setState(() {}),
      ),
      if (results.isNotEmpty) ...[
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFe2e8f0)),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8, offset: const Offset(0, 4))],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: results.length,
            separatorBuilder: (context, i) =>
                const Divider(height: 1, color: Color(0xFFF0F4F8)),
            itemBuilder: (_, i) {
              final c = results[i];
              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedCustomer = c;
                    _searchCtrl.clear();
                  });
                  _loadVehicles(c['uid'] as String);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c['name'] as String? ?? '—',
                          style: const TextStyle(fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1a202c))),
                      const SizedBox(height: 1),
                      Text(c['email'] as String? ?? '',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF718096))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2 — VEHICLE
  // ─────────────────────────────────────────────────────────────────────────

  Widget _step2Vehicle() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _lbl('2. VEHICLE'),
      if (_loadingVehicles)
        const Row(children: [
          SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Loading vehicles…',
              style: TextStyle(fontSize: 12, color: Color(0xFF718096))),
        ])
      else if (_vehicles.isEmpty)
        const Text('No vehicles found for this customer.',
            style: TextStyle(fontSize: 12, color: Color(0xFF718096)))
      else
        ..._vehicles.map((v) {
          final isSel = _selectedVehicle?['id'] == v['id'];
          final sub   = [v['year'], v['make'], v['model']]
              .where((x) => x != null && x.toString().isNotEmpty)
              .join(' ');
          return GestureDetector(
            onTap: () => setState(() => _selectedVehicle = v),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSel ? const Color(0xFFFFF5F5) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isSel ? _red : const Color(0xFFe2e8f0),
                    width: isSel ? 2 : 1.5),
              ),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                      color: isSel ? _red : const Color(0xFFe2e8f0),
                      borderRadius: BorderRadius.circular(9)),
                  child: Icon(Icons.directions_car_outlined,
                      size: 18,
                      color: isSel ? Colors.white : const Color(0xFF718096)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(v['plate'] as String? ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w700,
                          fontSize: 13, color: Color(0xFF1a202c))),
                  if (sub.isNotEmpty)
                    Text(sub, style: const TextStyle(
                        fontSize: 11, color: Color(0xFF718096))),
                ])),
                if (isSel)
                  const Icon(Icons.check_circle, size: 18, color: _red),
              ]),
            ),
          );
        }),
    ],
  );

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 3 — SERVICES
  // ─────────────────────────────────────────────────────────────────────────

  Widget _step3Services() {
    final count = _selectedServices.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lbl('3. SERVICES'),
      GestureDetector(
        onTap: _showServicesSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: count > 0 ? _red : const Color(0xFFcbd5e0),
                width: 1.5),
          ),
          child: Row(children: [
            const Icon(Icons.add_circle_outline, size: 16,
                color: Color(0xFF718096)),
            const SizedBox(width: 8),
            Text(
              count > 0
                  ? '$count service${count > 1 ? 's' : ''} selected'
                  : 'Select services…',
              style: TextStyle(
                  fontSize: 13,
                  color: count > 0 ? _red : const Color(0xFF718096),
                  fontWeight: count > 0
                      ? FontWeight.w600 : FontWeight.normal),
            ),
          ]),
        ),
      ),
      if (count > 0) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6,
          children: _selectedServices.keys.map((id) {
            final svc = _allServices.firstWhere((s) => s['id'] == id,
                orElse: () => <String, dynamic>{'name': id});
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5F5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFfeb2b2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(svc['name'] as String? ?? id,
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w600, color: _red)),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () =>
                      setState(() => _selectedServices.remove(id)),
                  child: const Icon(Icons.close, size: 13,
                      color: Color(0xFF718096)),
                ),
              ]),
            );
          }).toList()),
      ],
    ]);
  }

  void _showServicesSheet() {
    _svcSrchCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) {
          final q = _svcSrchCtrl.text.toLowerCase();
          final visible = _allServices.where((s) {
            final name = (s['name'] as String? ?? '').toLowerCase();
            final grp  = ((s['commodityGroup'] ?? s['group'] ?? '') as Object)
                .toString().toLowerCase();
            return q.isEmpty || name.contains(q) || grp.contains(q);
          }).toList();

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (_, ctrl2) => Column(children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [_red, Color(0xFFb5001a)]),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  const Expanded(child: Text('Select Services',
                      style: TextStyle(color: Colors.white, fontSize: 15,
                          fontWeight: FontWeight.w700))),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx2),
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                          color: Colors.white24, shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(children: [
                  Expanded(child: TextField(
                    controller: _svcSrchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search services…',
                      prefixIcon: const Icon(Icons.search, size: 17,
                          color: Color(0xFFa0aec0)),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      filled: true, fillColor: const Color(0xFFF8FAFC),
                    ),
                    onChanged: (_) => setInner(() {}),
                  )),
                  if (_selectedServices.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Text('${_selectedServices.length} selected',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: _red)),
                  ],
                ]),
              ),
              Expanded(
                child: _loadingServices
                    ? const Center(child: CircularProgressIndicator())
                    : visible.isEmpty
                        ? const Center(child: Text('No services found.',
                            style: TextStyle(color: Color(0xFF718096))))
                        : ListView.separated(
                            controller: ctrl2,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: visible.length,
                            separatorBuilder: (context, i) =>
                                const SizedBox(height: 6),
                            itemBuilder: (_, i) {
                              final s   = visible[i];
                              final id  = s['id'] as String;
                              final sel = _selectedServices[id] ?? false;
                              final grp = ((s['commodityGroup'] ??
                                  s['group'] ?? '') as Object).toString();
                              final cost = s['cost'];
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (sel) {
                                      _selectedServices.remove(id);
                                    } else {
                                      _selectedServices[id] = true;
                                    }
                                  });
                                  setInner(() {});
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: sel
                                        ? const Color(0xFFFFF5F5)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: sel
                                          ? const Color(0xFFfeb2b2)
                                          : const Color(0xFFe2e8f0),
                                    ),
                                  ),
                                  child: Row(children: [
                                    Container(
                                      width: 22, height: 22,
                                      decoration: BoxDecoration(
                                        color: sel ? _red : Colors.white,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                            color: sel
                                                ? _red
                                                : const Color(0xFFe2e8f0),
                                            width: 2),
                                      ),
                                      child: sel
                                          ? const Icon(Icons.check,
                                              size: 14, color: Colors.white)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(s['name'] as String? ?? '—',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF1a202c))),
                                      if (grp.isNotEmpty)
                                        Text(grp, style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF718096))),
                                    ])),
                                    if (cost != null)
                                      Text('₱$cost',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: _red)),
                                  ]),
                                ),
                              );
                            },
                          ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx2),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    child: const Text('Done',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 4 — CALENDAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _step4Calendar() {
    final now     = DateTime.now();
    final today   = DateTime(now.year, now.month, now.day);
    final firstWd = DateTime(_calYear, _calMonth, 1).weekday % 7;
    final days    = DateTime(_calYear, _calMonth + 1, 0).day;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lbl('4. PREFERRED DATE'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFe2e8f0)),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _calBtn(-1),
            Text('${_months[_calMonth - 1]} $_calYear',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            _calBtn(1),
          ]),
          const SizedBox(height: 10),
          Row(
            children: ['SU','MO','TU','WE','TH','FR','SA']
                .map((d) => Expanded(
                  child: Center(
                    child: Text(d, style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w700,
                        color: Color(0xFFa0aec0))),
                  ),
                ))
                .toList(),
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 3, crossAxisSpacing: 3,
              childAspectRatio: 1.2,
            ),
            itemCount: firstWd + days,
            itemBuilder: (_, idx) {
              if (idx < firstWd) return const SizedBox.shrink();
              final day = idx - firstWd + 1;
              final dt  = DateTime(_calYear, _calMonth, day);
              final key = '$_calYear-'
                  '${_calMonth.toString().padLeft(2, '0')}-'
                  '${day.toString().padLeft(2, '0')}';
              final isPast = dt.isBefore(today);
              final isSel  = key == _selectedDate;
              final taken  = _bookedSlots[key] ?? [];
              final isFull = taken.length >= _allSlots.length;
              final disabled = isPast || isFull;

              Color bg, tc;
              if (isSel) {
                bg = _red; tc = Colors.white;
              } else if (isPast) {
                bg = const Color(0xFFF1F5F9);
                tc = const Color(0xFFcbd5e0);
              } else if (isFull) {
                bg = const Color(0xFFFEF3C7);
                tc = const Color(0xFF92400E);
              } else {
                bg = const Color(0xFFF0FDF4);
                tc = const Color(0xFF1a202c);
              }

              return GestureDetector(
                onTap: disabled
                    ? null
                    : () => setState(() {
                        _selectedDate = key;
                        _selectedTime = '';
                      }),
                child: Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: isSel
                        ? [BoxShadow(
                            color: _red.withValues(alpha: 0.3),
                            blurRadius: 6)]
                        : null,
                  ),
                  child: Center(
                    child: Text('$day',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w600, color: tc)),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legend(const Color(0xFF38a169), 'Available'),
              const SizedBox(width: 14),
              _legend(const Color(0xFFd97706), 'Full'),
            ],
          ),
        ]),
      ),
    ]);
  }

  Widget _calBtn(int dir) => GestureDetector(
    onTap: () => setState(() {
      _calMonth += dir;
      if (_calMonth > 12) { _calMonth = 1;  _calYear++; }
      if (_calMonth < 1)  { _calMonth = 12; _calYear--; }
    }),
    child: Container(
      width: 30, height: 30,
      decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFe2e8f0)),
          borderRadius: BorderRadius.circular(8)),
      child: Icon(
          dir < 0 ? Icons.chevron_left : Icons.chevron_right,
          size: 18, color: const Color(0xFF4a5568)),
    ),
  );

  Widget _legend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(
          fontSize: 10, color: Color(0xFF718096))),
    ],
  );

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 5 — TIME
  // ─────────────────────────────────────────────────────────────────────────

  Widget _step5Time() {
    final taken = _bookedSlots[_selectedDate] ?? [];
    final ab    = _arriveBy[_selectedTime];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lbl('5. PREFERRED TIME'),
      const Text('Customer should arrive 15 minutes before.',
          style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
      const SizedBox(height: 10),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 4,
        mainAxisSpacing: 8, crossAxisSpacing: 8,
        childAspectRatio: 2.2,
        children: _allSlots.map((t) {
          final isTaken = taken.contains(t);
          final isSel   = t == _selectedTime;
          return GestureDetector(
            onTap: isTaken
                ? null
                : () => setState(() => _selectedTime = t),
            child: Container(
              decoration: BoxDecoration(
                color: isTaken
                    ? const Color(0xFFF1F5F9)
                    : isSel
                        ? const Color(0xFFFFF5F5)
                        : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isTaken
                      ? const Color(0xFFe2e8f0)
                      : isSel
                          ? _red
                          : const Color(0xFFe2e8f0),
                  width: isSel ? 2 : 1.5,
                ),
              ),
              child: Center(
                child: Text(t,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isTaken
                          ? const Color(0xFFa0aec0)
                          : isSel
                              ? _red
                              : const Color(0xFF4a5568),
                      decoration: isTaken
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: const Color(0xFFa0aec0),
                    )),
              ),
            ),
          );
        }).toList(),
      ),
      if (ab != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFC6F6D5)),
          ),
          child: Row(children: [
            const Icon(Icons.access_time, size: 13, color: Color(0xFF38A169)),
            const SizedBox(width: 6),
            Text('Customer arrives by: $ab',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF276749),
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
    ]);
  }

  // ── Notes ─────────────────────────────────────────────────────────────────

  Widget _notes() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _lbl('NOTES (OPTIONAL)'),
      TextField(
        controller: _notesCtrl,
        maxLines: 2,
        decoration: InputDecoration(
          hintText: 'Any special instructions…',
          isDense: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _red)),
          filled: true, fillColor: const Color(0xFFF8FAFC),
        ),
      ),
    ],
  );

  // ── Summary ───────────────────────────────────────────────────────────────

  Widget _summary() {
    if (!_canSubmit) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF38a169)),
      ),
      child: Column(children: [
        Text('📅 ${_fmtLong(_selectedDate)}',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: Color(0xFF38a169))),
        const SizedBox(height: 2),
        Text('🕐 $_selectedTime',
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF276749))),
        const SizedBox(height: 6),
        Text(
          '${_selectedVehicle!['plate']}  •  '
          '${_selectedServices.length} service${_selectedServices.length > 1 ? 's' : ''}',
          style: const TextStyle(
              fontSize: 11, color: Color(0xFF276749)),
        ),
      ]),
    );
  }

  // ── Submit button ─────────────────────────────────────────────────────────

  Widget _submitBtn() => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: _canSubmit && !_saving ? _submit : null,
      icon: _saving
          ? const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.calendar_month_outlined, size: 16),
      label: Text(_saving ? 'Booking…' : 'Book Service',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _red,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _red.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white70,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
