import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'customer_mybookings.dart';

class CustomerBookService extends StatefulWidget {
  /// When [embedded] is true (inside a TabBarView), the AppBar is hidden.
  final bool embedded;

  /// When set, this vehicle will be pre-selected on load.
  final String? preselectedVehicleId;
  const CustomerBookService({
    super.key,
    this.embedded = false,
    this.preselectedVehicleId,
  });

  @override
  State<CustomerBookService> createState() => _CustomerBookServiceState();
}

class _CustomerBookServiceState extends State<CustomerBookService> {
  static const _red = Color(0xFFE8001C);

  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _vehicles = [];
  final Set<String> _selectedVehicleIds = {};
  // Per-vehicle service selections: vehicleId ? Set of service IDs
  final Map<String, Set<String>> _vehicleServices = {};
  DateTime? _preferredDate;
  String? _preferredTime;
  String _notes = '';
  bool _loading = true;
  bool _submitting = false;

  static const _allTimeSlots = [
    '8:00 AM',
    '9:00 AM',
    '10:00 AM',
    '11:00 AM',
    '1:00 PM',
    '2:00 PM',
    '3:00 PM',
    '4:00 PM',
  ];

  // Calendar state
  late int _calYear;
  late int _calMonth;
  Map<String, List<String>> _bookedDates =
      {}; // date ? list of taken time slots
  Map<String, List<String>> _bookedTimes =
      {}; // date ? list of taken time slots (alias, reused from _bookedDates)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calYear = now.year;
    _calMonth = now.month;
    _loadData();
    _loadBookedDates();
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Load services from item_master (type = 'Service')
    final svcSnap = await FirebaseFirestore.instance
        .collection('item_master')
        .get();

    final serviceItems = svcSnap.docs
        .where((d) {
          final data = d.data();
          final type =
              (data['type'] as String? ?? data['itemType'] as String? ?? '')
                  .toLowerCase();
          return type == 'service';
        })
        .map((d) => {'id': d.id, ...d.data()})
        .toList();

    // Load user's vehicles
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final userName = (userDoc.data()?['name'] as String? ?? '')
        .toLowerCase()
        .trim();
    final companyName = (userDoc.data()?['companyName'] as String? ?? '')
        .toLowerCase()
        .trim();

    final vehSnap = await FirebaseFirestore.instance
        .collection('vehicles')
        .get();
    final myVehicles = vehSnap.docs
        .where((d) {
          final data = d.data();
          final owner = (data['owner'] as String? ?? '').toLowerCase().trim();
          // Match if vehicle owner equals the user's name OR their company name
          // Also match if ownerId field equals the current uid
          final ownerId = (data['ownerId'] as String? ?? '').trim();
          return (userName.isNotEmpty && owner == userName) ||
              (companyName.isNotEmpty && owner == companyName) ||
              (ownerId.isNotEmpty && ownerId == uid);
        })
        .map((d) => {'id': d.id, ...d.data()})
        .toList();

    if (mounted) {
      setState(() {
        _services = serviceItems;
        _vehicles = myVehicles;
        _loading = false;
      });
      // Auto-select pre-selected vehicle if provided
      if (widget.preselectedVehicleId != null) {
        final vId = widget.preselectedVehicleId!;
        if (myVehicles.any((v) => v['id'] == vId)) {
          setState(() {
            _selectedVehicleIds.add(vId);
            _vehicleServices.putIfAbsent(vId, () => <String>{});
          });
        }
      }
    }
  }

  Future<void> _loadBookedDates() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('service_bookings')
          .where('status', whereIn: ['Approved', 'Pending'])
          .get();
      final Map<String, List<String>> slots = {};
      for (final doc in snap.docs) {
        final date = doc.data()['preferredDate'] as String?;
        final time = doc.data()['preferredTime'] as String?;
        if (date != null && time != null && time.isNotEmpty) {
          slots.putIfAbsent(date, () => []);
          if (!slots[date]!.contains(time)) slots[date]!.add(time);
        }
      }
      if (mounted)
        setState(() {
          _bookedDates = slots;
          _bookedTimes = Map.from(slots); // share the same data
        });
    } catch (_) {}
  }

  Future<void> _loadBookedTimesForDate(String dateStr) async {
    if (_bookedTimes.containsKey(dateStr)) return;
    // Reuse already-loaded slot data if available
    if (_bookedDates.isNotEmpty) {
      if (mounted)
        setState(() => _bookedTimes[dateStr] = _bookedDates[dateStr] ?? []);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('service_bookings')
          .where('preferredDate', isEqualTo: dateStr)
          .where('status', whereIn: ['Approved', 'Pending'])
          .get();
      final times = snap.docs
          .map((d) => d.data()['preferredTime'] as String?)
          .where((t) => t != null && t.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();
      if (mounted) setState(() => _bookedTimes[dateStr] = times);
    } catch (_) {
      if (mounted) setState(() => _bookedTimes[dateStr] = []);
    }
  }

  Future<void> _submitBooking() async {
    if (_selectedVehicleIds.isEmpty) {
      _snack('Please select at least one vehicle.');
      return;
    }
    // Check each selected vehicle has at least one service
    for (final vId in _selectedVehicleIds) {
      final svcs = _vehicleServices[vId] ?? {};
      if (svcs.isEmpty) {
        final vehicle = _vehicles.firstWhere(
          (v) => v['id'] == vId,
          orElse: () => <String, dynamic>{},
        );
        final plate = vehicle['plate'] as String? ?? 'a vehicle';
        _snack('Please select services for $plate.');
        return;
      }
    }
    if (_preferredDate == null) {
      _snack('Please select a preferred date.');
      return;
    }
    if (_preferredTime == null) {
      _snack('Please select a preferred start time.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final db = FirebaseFirestore.instance;
      final userDoc = await db.collection('users').doc(uid).get();
      final customerName = userDoc.data()?['name'] as String? ?? '';

      final selectedVehicles = _vehicles
          .where((v) => _selectedVehicleIds.contains(v['id']))
          .toList();

      final dateStr =
          '${_preferredDate!.year}-${_preferredDate!.month.toString().padLeft(2, '0')}-${_preferredDate!.day.toString().padLeft(2, '0')}';

      // Create one booking per selected vehicle � always Approved
      for (final vehicle in selectedVehicles) {
        final plate = vehicle['plate'] as String? ?? '';
        final vehicleDesc = vehicle['desc'] as String? ?? '';
        final vId = vehicle['id'] as String;
        final vSvcIds = _vehicleServices[vId] ?? {};
        final vServiceNames = _services
            .where((s) => vSvcIds.contains(s['id']))
            .map((s) => s['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList();

        await db.collection('service_bookings').add({
          'customerId': uid,
          'customerName': customerName,
          'vehicleId': vId,
          'plate': plate,
          'vehicleDesc': vehicleDesc,
          'services': vServiceNames,
          'preferredDate': dateStr,
          'preferredTime': _preferredTime,
          'notes': _notes.trim(),
          'status': 'Approved',
          'autoApproved': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Build per-vehicle service breakdown for notifications
      final vehicleBreakdown = <String>[];
      for (final vehicle in selectedVehicles) {
        final vId = vehicle['id'] as String;
        final plate = vehicle['plate'] as String? ?? '�';
        final vSvcIds = _vehicleServices[vId] ?? {};
        final vNames = _services
            .where((s) => vSvcIds.contains(s['id']))
            .map((s) => s['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        vehicleBreakdown.add('$plate: ${vNames.join(", ")}');
      }
      final detailedMsg = vehicleBreakdown.join(' | ');
      final vCount = selectedVehicles.length;
      final vLabel = '$vCount vehicle${vCount > 1 ? 's' : ''}';
      final bookingMsg =
          '$customerName booked service for $vLabel on ${_fmtDatePretty(_preferredDate!)}. $detailedMsg';

      // -- Load admin & staff UIDs --
      final adminSnap = await db
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();
      final staffSnap2 = await db
          .collection('users')
          .where('role', isEqualTo: 'staff')
          .get();
      final adminUids = adminSnap.docs.map((d) => d.id).toList();
      final staffUids = staffSnap2.docs.map((d) => d.id).toList();

      // -- Notify admin: in-app + push --
      await _sendAlertToUsers(
        db: db,
        uids: adminUids,
        title: '?? New Booking � $vLabel',
        message: bookingMsg,
        type: 'info',
        targetRole: 'admin',
      );

      // -- Notify staff: in-app + push --
      await _sendAlertToUsers(
        db: db,
        uids: staffUids,
        title: '?? New Booking � $vLabel',
        message: bookingMsg,
        type: 'info',
        targetRole: 'staff',
      );

      // -- Email admin & staff via Flask (server fetches recipient emails) --
      _sendBookingEmail(
        customerName: customerName,
        selectedVehicles: selectedVehicles,
        vehicleServices: _vehicleServices,
        services: _services,
        preferredDate: _fmtDatePretty(_preferredDate!),
        preferredTime: _preferredTime!,
        notes: _notes,
      ); // fire-and-forget � don't await so UI isn't blocked

      // -- Notify customer: in-app only --
      await db.collection('notifications').add({
        'title': '? Booking Confirmed',
        'message':
            'Your service booking on ${_fmtDatePretty(_preferredDate!)} at $_preferredTime has been confirmed.\n$detailedMsg',
        'type': 'success',
        'targetRole': '',
        'targetUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'readBy': <String, bool>{},
        'isRead': false,
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CustomerMyBookings()),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '? Booking confirmed for $vCount vehicle${vCount > 1 ? 's' : ''}!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Sends in-app Firestore notification + OneSignal push to each uid.
  /// Email is sent separately via _sendBookingEmail (Flask handles recipient lookup).
  Future<void> _sendAlertToUsers({
    required FirebaseFirestore db,
    required List<String> uids,
    required String title,
    required String message,
    required String type,
    String targetRole = '',
    String targetUid = '',
  }) async {
    if (uids.isEmpty) return;

    // 1. In-app notification (one doc per role so all members see it)
    await db.collection('notifications').add({
      'title': title,
      'message': message,
      'type': type,
      'targetRole': targetRole,
      'targetUid': targetUid,
      'readBy': <String, bool>{},
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2. OneSignal push notification
    const oneSignalAppId = 'c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea';
    const oneSignalApiKey =
        'os_v2_app_yt4cvr2tibhhvb35du4k637i5l5mjeywytben3fd6lmzeiyhnrp6hzfi3uq77vkidwssmkrud4mdada7wp3sg2dpybuk4vrrtc7cs7y';
    try {
      await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Authorization': 'Basic $oneSignalApiKey',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'app_id': oneSignalAppId,
          'include_aliases': {'external_id': uids},
          'target_channel': 'push',
          'headings': {'en': title},
          'contents': {'en': message},
          'data': {'type': type},
          'android_channel_id': 'autopro_alerts',
          'ios_sound': 'default',
        }),
      );
    } catch (e) {
      debugPrint('? OneSignal push error: $e');
    }
  }

  /// Calls Flask /api/send-booking-email � server fetches admin/staff emails
  /// from Firestore and sends a rich HTML booking notification email.
  Future<void> _sendBookingEmail({
    required String customerName,
    required List<Map<String, dynamic>> selectedVehicles,
    required Map<String, Set<String>> vehicleServices,
    required List<Map<String, dynamic>> services,
    required String preferredDate,
    required String preferredTime,
    required String notes,
  }) async {
    const flaskBaseUrl = 'https://caltex-autopro.onrender.com';
    try {
      final vehiclePayload = selectedVehicles.map((v) {
        final vId = v['id'] as String;
        final plate = v['plate'] as String? ?? '�';
        final desc = v['desc'] as String? ?? '';
        final svcIds = vehicleServices[vId] ?? {};
        final svcNames = services
            .where((s) => svcIds.contains(s['id']))
            .map((s) => s['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        return {'plate': plate, 'desc': desc, 'services': svcNames};
      }).toList();

      await http.post(
        Uri.parse('$flaskBaseUrl/api/send-booking-email'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'customer_name': customerName,
          'vehicles': vehiclePayload,
          'preferred_date': preferredDate,
          'preferred_time': preferredTime,
          'notes': notes,
          'target_roles': ['admin', 'staff'],
        }),
      );
    } catch (e) {
      debugPrint('? Booking email dispatch error: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: widget.embedded
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF004B5F),
              elevation: 0,
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF004B5F), Color(0xFFEE152A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text(
                'Book a Service',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // -- Select Vehicle(s) --
                  _sectionTitle('Select Vehicle(s)'),
                  const SizedBox(height: 8),
                  if (_vehicles.isEmpty)
                    _emptyCard('No vehicles found under your account.')
                  else
                    ..._vehicles.map((v) => _vehicleTile(v)),

                  // -- Per-vehicle service selection --
                  if (_selectedVehicleIds.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionTitle('Select Services'),
                    const SizedBox(height: 12),
                    ..._selectedVehicleIds.map((vId) {
                      final vehicle = _vehicles.firstWhere(
                        (v) => v['id'] == vId,
                        orElse: () => <String, dynamic>{},
                      );
                      final plate = vehicle['plate'] as String? ?? '�';
                      final desc = vehicle['desc'] as String? ?? '';
                      final selectedSvcs = _vehicleServices[vId] ?? {};
                      final selectedNames = _services
                          .where((s) => selectedSvcs.contains(s['id']))
                          .map((s) => s['name'] as String? ?? '')
                          .where((n) => n.isNotEmpty)
                          .toList();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selectedSvcs.isNotEmpty
                                ? _red.withOpacity(0.3)
                                : const Color(0xFFe2e8f0),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
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
                                    plate,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1a202c),
                                    ),
                                  ),
                                  if (desc.isNotEmpty)
                                    Text(
                                      desc,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF718096),
                                      ),
                                    ),
                                  if (selectedNames.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: selectedNames
                                          .map(
                                            (n) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFF5F5),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: _red.withOpacity(0.3),
                                                ),
                                              ),
                                              child: Text(
                                                n,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: _red,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () => _showServiceModal(vId, plate),
                              child: selectedSvcs.isNotEmpty
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF5F5),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFFFCA5A5),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.edit_outlined,
                                            size: 13,
                                            color: _red,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Edit (${selectedSvcs.length})',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: _red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF5F5),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFFFCA5A5),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.add,
                                            size: 14,
                                            color: _red,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Select Services',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: _red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 20),

                  // -- Preferred Date --
                  _sectionTitle('Preferred Date'),
                  const SizedBox(height: 8),
                  // Date display field (like website's "Tap to select date" button)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _preferredDate != null
                            ? _red
                            : const Color(0xFFe2e8f0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: _preferredDate != null
                              ? _red
                              : const Color(0xFF718096),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _preferredDate != null
                              ? _fmtDatePretty(_preferredDate!)
                              : 'Select a date from the calendar below',
                          style: TextStyle(
                            fontSize: 14,
                            color: _preferredDate != null
                                ? const Color(0xFF1a202c)
                                : const Color(0xFFa0aec0),
                            fontWeight: _preferredDate != null
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Custom Calendar
                  _buildCalendar(),

                  const SizedBox(height: 20),

                  // -- Preferred Start Time --
                  _sectionTitle('Preferred Start Time'),
                  const SizedBox(height: 4),
                  const Text(
                    'Please arrive 15 minutes before your selected time.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF718096)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      '8:00 AM',
                      '9:00 AM',
                      '10:00 AM',
                      '11:00 AM',
                      '1:00 PM',
                      '2:00 PM',
                      '3:00 PM',
                      '4:00 PM',
                    ].map((time) => _timeChip(time)).toList(),
                  ),
                  if (_preferredTime != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFC6F6D5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: 14,
                            color: Color(0xFF38A169),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Arrive by: ${_getArriveBy(_preferredTime!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF276749),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // -- Notes --
                  _sectionTitle('Notes (optional)'),
                  const SizedBox(height: 8),
                  TextField(
                    maxLines: 3,
                    onChanged: (v) => _notes = v,
                    decoration: InputDecoration(
                      hintText: 'Any special requests or details...',
                      hintStyle: const TextStyle(
                        color: Color(0xFFa0aec0),
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFe2e8f0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFe2e8f0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _red, width: 1.5),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // -- Submit --
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF004B5F), Color(0xFFEE152A)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF004B5F).withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submitBooking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Book Service',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  void _showServiceModal(String vehicleId, String plate) {
    final localSelected = Set<String>.from(_vehicleServices[vehicleId] ?? {});
    final searchCtrl = TextEditingController();
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final filtered = searchQuery.isEmpty
              ? _services
              : _services
                    .where(
                      (s) => (s['name'] as String? ?? '')
                          .toLowerCase()
                          .contains(searchQuery),
                    )
                    .toList();

          // Keyboard height � shrinks modal up so nothing overflows
          final keyboardH = MediaQuery.of(ctx).viewInsets.bottom;
          final screenH = MediaQuery.of(ctx).size.height;

          return Padding(
            padding: EdgeInsets.only(bottom: keyboardH),
            child: SizedBox(
              // Cap total modal height so it never overflows
              height: screenH * 0.82,
              child: Column(
                children: [
                  // -- Header --
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    decoration: const BoxDecoration(
                      color: _red,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Select Services',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                plate,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  // -- Search bar --
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: TextField(
                      controller: searchCtrl,
                      onChanged: (v) =>
                          setSheet(() => searchQuery = v.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Search services...',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFa0aec0),
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          size: 18,
                          color: Color(0xFF718096),
                        ),
                        suffixIcon: searchQuery.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  searchCtrl.clear();
                                  setSheet(() => searchQuery = '');
                                },
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Color(0xFF718096),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFF7F8FA),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFe2e8f0),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _red, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  // -- Count label --
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          filtered.isEmpty
                              ? 'No results'
                              : '${filtered.length} service${filtered.length != 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF718096),
                          ),
                        ),
                        if (localSelected.isNotEmpty)
                          Text(
                            '${localSelected.length} selected',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _red,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // -- Service list � Expanded fills remaining space --
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              searchQuery.isNotEmpty
                                  ? 'No services match "$searchQuery"'
                                  : 'No services available.',
                              style: const TextStyle(
                                color: Color(0xFF718096),
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final s = filtered[i];
                              final id = s['id'] as String;
                              final isSelected = localSelected.contains(id);
                              final name = (s['name'] ?? '').toString();
                              final rawCost = (s['cost'] ?? '')
                                  .toString()
                                  .replaceAll('?', '')
                                  .replaceAll(',', '')
                                  .trim();
                              final costDisplay = rawCost.isNotEmpty
                                  ? '?$rawCost'
                                  : '';
                              final uom = (s['uom'] ?? '').toString();

                              return GestureDetector(
                                onTap: () => setSheet(() {
                                  if (isSelected)
                                    localSelected.remove(id);
                                  else
                                    localSelected.add(id);
                                }),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFFFF5F5)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? _red
                                          : const Color(0xFFe2e8f0),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.03),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? _red
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? _red
                                                : const Color(0xFFcbd5e0),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: isSelected
                                            ? const Icon(
                                                Icons.check,
                                                size: 14,
                                                color: Colors.white,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: isSelected
                                                    ? _red
                                                    : const Color(0xFF1a202c),
                                              ),
                                            ),
                                            if (costDisplay.isNotEmpty)
                                              Text(
                                                '$costDisplay / $uom',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF718096),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(
                                          Icons.check_circle,
                                          size: 18,
                                          color: _red,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  // -- Done button --
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(
                            () => _vehicleServices[vehicleId] = localSelected,
                          );
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          localSelected.isEmpty
                              ? 'Done'
                              : 'Confirm ${localSelected.length} Service${localSelected.length > 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _monthsFull = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  Widget _buildCalendar() {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final firstDayOfMonth = DateTime(_calYear, _calMonth, 1);
    final daysInMonth = DateTime(_calYear, _calMonth + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday % 7; // Sunday = 0

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        children: [
          // Header: nav + month label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => setState(() {
                  _calMonth--;
                  if (_calMonth < 1) {
                    _calMonth = 12;
                    _calYear--;
                  }
                }),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFe2e8f0)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.chevron_left,
                    size: 18,
                    color: Color(0xFF4a5568),
                  ),
                ),
              ),
              Text(
                '${_monthsFull[_calMonth - 1]} $_calYear',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1a202c),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _calMonth++;
                  if (_calMonth > 12) {
                    _calMonth = 1;
                    _calYear++;
                  }
                }),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFe2e8f0)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Color(0xFF4a5568),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Day of week headers
          Row(
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFa0aec0),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6),
          // Calendar grid
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              // Empty cells before first day
              ...List.generate(startWeekday, (_) => const SizedBox.shrink()),
              // Day cells
              ...List.generate(daysInMonth, (i) {
                final day = i + 1;
                final date = DateTime(_calYear, _calMonth, day);
                final dateStr =
                    '${_calYear}-${_calMonth.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                final isPast = date.isBefore(todayMidnight);
                final takenSlots = _bookedDates[dateStr] ?? [];
                final isFull = takenSlots.length >= _allTimeSlots.length;
                final isSelected =
                    _preferredDate != null &&
                    _preferredDate!.year == _calYear &&
                    _preferredDate!.month == _calMonth &&
                    _preferredDate!.day == day;
                final isClosed = isPast;
                final isAvailable = !isClosed && !isFull;

                Color bgColor;
                Color textColor;
                Color dotColor;
                if (isSelected) {
                  bgColor = _red;
                  textColor = Colors.white;
                  dotColor = Colors.white70;
                } else if (isClosed) {
                  bgColor = const Color(0xFFF1F5F9);
                  textColor = const Color(0xFFcbd5e0);
                  dotColor = const Color(0xFFcbd5e0);
                } else if (isFull) {
                  bgColor = const Color(0xFFFEF3C7);
                  textColor = const Color(0xFF92400E);
                  dotColor = const Color(0xFFD97706);
                } else {
                  bgColor = const Color(0xFFF0FDF4);
                  textColor = const Color(0xFF1a202c);
                  dotColor = const Color(0xFF38A169);
                }

                return GestureDetector(
                  onTap: isAvailable
                      ? () {
                          final dateStr2 =
                              '$_calYear-${_calMonth.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                          setState(() {
                            _preferredDate = date;
                            // Reset time if changing date
                            _preferredTime = null;
                          });
                          _loadBookedTimesForDate(dateStr2);
                        }
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(color: _red, width: 2)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          // Legend
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF0F4F8))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendItem(const Color(0xFF38A169), 'Available'),
                const SizedBox(width: 16),
                _legendDot(
                  const Color(0xFFD97706),
                  const Color(0xFFFEF3C7),
                  'Fully Booked',
                ),
                const SizedBox(width: 16),
                _legendItem(const Color(0xFFe2e8f0), 'Closed / Past'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
        ),
      ],
    );
  }

  Widget _legendDot(Color borderColor, Color bgColor, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
        ),
      ],
    );
  }

  static const _arriveByMap = {
    '8:00 AM': '7:45 AM',
    '9:00 AM': '8:45 AM',
    '10:00 AM': '9:45 AM',
    '11:00 AM': '10:45 AM',
    '1:00 PM': '12:45 PM',
    '2:00 PM': '1:45 PM',
    '3:00 PM': '2:45 PM',
    '4:00 PM': '3:45 PM',
  };

  String _getArriveBy(String time) => _arriveByMap[time] ?? time;

  Widget _timeChip(String time) {
    final isSelected = _preferredTime == time;
    // Check if this time is taken for the selected date
    final dateStr = _preferredDate != null
        ? '${_preferredDate!.year}-${_preferredDate!.month.toString().padLeft(2, '0')}-${_preferredDate!.day.toString().padLeft(2, '0')}'
        : '';
    final isTaken =
        dateStr.isNotEmpty && (_bookedTimes[dateStr]?.contains(time) ?? false);

    // Check if the slot has already passed (only applies when selected date is today)
    bool isPast = false;
    if (_preferredDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final selected = DateTime(
        _preferredDate!.year,
        _preferredDate!.month,
        _preferredDate!.day,
      );
      if (selected == today) {
        const slotHour24 = {
          '8:00 AM': 8,
          '9:00 AM': 9,
          '10:00 AM': 10,
          '11:00 AM': 11,
          '1:00 PM': 13,
          '2:00 PM': 14,
          '3:00 PM': 15,
          '4:00 PM': 16,
        };
        final h = slotHour24[time];
        if (h != null) isPast = now.hour >= h;
      }
    }

    final isDisabled = isTaken || isPast || _preferredDate == null;
    final tooltip = isPast
        ? 'This time has already passed'
        : isTaken
        ? 'Already booked � choose another time'
        : '';

    return GestureDetector(
      onTap: isDisabled ? null : () => setState(() => _preferredTime = time),
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: (isTaken || isPast)
                ? const Color(0xFFF1F5F9)
                : isSelected
                ? const Color(0xFFFFF5F5)
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: (isTaken || isPast)
                  ? const Color(0xFFe2e8f0)
                  : isSelected
                  ? _red
                  : const Color(0xFFe2e8f0),
              width: isSelected ? 2 : 1.5,
            ),
          ),
          child: Text(
            time,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: (isTaken || isPast)
                  ? const Color(0xFFa0aec0)
                  : isSelected
                  ? _red
                  : const Color(0xFF4a5568),
              decoration: (isTaken || isPast)
                  ? TextDecoration.lineThrough
                  : null,
              decorationColor: const Color(0xFFa0aec0),
            ),
          ),
        ),
      ),
    );
  }

  String _fmtDatePretty(DateTime d) {
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Widget _sectionTitle(String title) => Text(
    title,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: Color(0xFF1a202c),
    ),
  );

  Widget _emptyCard(String msg) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFe2e8f0)),
    ),
    child: Text(
      msg,
      style: const TextStyle(color: Color(0xFF718096), fontSize: 13),
      textAlign: TextAlign.center,
    ),
  );

  Widget _vehicleTile(Map<String, dynamic> v) {
    final id = v['id'] as String;
    final isSelected = _selectedVehicleIds.contains(id);
    return GestureDetector(
      onTap: () => setState(() {
        if (isSelected) {
          _selectedVehicleIds.remove(id);
          _vehicleServices.remove(id);
        } else {
          _selectedVehicleIds.add(id);
          _vehicleServices.putIfAbsent(id, () => <String>{});
        }
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF5F5) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _red : const Color(0xFFe2e8f0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v['plate'] as String? ?? '�',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isSelected ? _red : const Color(0xFF1a202c),
                    ),
                  ),
                  Text(
                    v['desc'] as String? ?? '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF718096),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_box : Icons.check_box_outline_blank,
              color: isSelected ? _red : const Color(0xFFcbd5e0),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _perVehicleServiceTile(String vehicleId, Map<String, dynamic> s) {
    final id = s['id'] as String;
    final svcs = _vehicleServices[vehicleId] ?? {};
    final isSelected = svcs.contains(id);
    final name = (s['name'] ?? '').toString();
    final rawCost = (s['cost'] ?? '')
        .toString()
        .replaceAll('?', '')
        .replaceAll(',', '')
        .trim();
    final costDisplay = rawCost.isNotEmpty ? '?$rawCost' : '';
    final uom = (s['uom'] ?? '').toString();

    return GestureDetector(
      onTap: () => setState(() {
        _vehicleServices.putIfAbsent(vehicleId, () => <String>{});
        if (isSelected) {
          _vehicleServices[vehicleId]!.remove(id);
        } else {
          _vehicleServices[vehicleId]!.add(id);
        }
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF5F5) : const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _red : const Color(0xFFF0F4F8),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isSelected ? _red : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isSelected ? _red : const Color(0xFFcbd5e0),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isSelected ? _red : const Color(0xFF1a202c),
                    ),
                  ),
                  if (costDisplay.isNotEmpty)
                    Text(
                      '$costDisplay / $uom',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF718096),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _serviceTile(Map<String, dynamic> s) {
    // Legacy � kept for compatibility but not used in new flow
    return _perVehicleServiceTile('', s);
  }
}
