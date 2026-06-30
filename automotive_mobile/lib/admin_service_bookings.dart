import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_vehicle_maintenance.dart';

class AdminServiceBookings extends StatelessWidget {
  const AdminServiceBookings({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF7F8FA),
      body: AdminServiceBookingsBody(),
    );
  }
}

/// Embeddable body — can be placed inside any parent (e.g. a tab in the dashboard).
class AdminServiceBookingsBody extends StatefulWidget {
  final String searchQuery;
  const AdminServiceBookingsBody({super.key, this.searchQuery = ''});

  @override
  State<AdminServiceBookingsBody> createState() => _AdminServiceBookingsBodyState();
}

class _AdminServiceBookingsBodyState extends State<AdminServiceBookingsBody> {
  static const _red = Color(0xFFE8001C);
  static const _blue = Color(0xFF003087);
  static const _months = ['January','February','March','April','May','June','July','August','September','October','November','December'];

  String _filter = 'all'; // 'all', 'Pending', 'Approved', 'Rescheduled', 'Dismissed'
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildList();
  }

  Widget _statChip(String label, String value, Color color, IconData icon, String filter) {
    final isActive = _filter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = _filter == filter ? 'all' : filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isActive ? color : Colors.transparent, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
          child: Column(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 15),
            ),
            const SizedBox(height: 5),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF718096))),
          ]),
        ),
      ),
    );
  }

  Widget _buildList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('service_bookings')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final allDocs = snapshot.data?.docs ?? [];
        final allBookings = allDocs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          return {...data, 'docId': d.id};
        }).where((d) {
          final status = d['status'] as String? ?? '';
          return status == 'Approved' || status == 'Dismissed' || status == 'Pending';
        }).toList();

        // Compute counts
        final approved = allBookings.where((d) => d['status'] == 'Approved' && !_isRescheduled(d)).length;
        final rescheduled = allBookings.where((d) => d['status'] == 'Approved' && _isRescheduled(d)).length;
        final cancelled = allBookings.where((d) => d['status'] == 'Dismissed').length;
        final pending = allBookings.where((d) => d['status'] == 'Pending').length;
        final total = allBookings.length;

        // Apply filter
        final afterFilter = _filter == 'all'
            ? allBookings
            : _filter == 'Rescheduled'
                ? allBookings.where((d) => d['status'] == 'Approved' && _isRescheduled(d)).toList()
                : _filter == 'Approved'
                    ? allBookings.where((d) => d['status'] == 'Approved' && !_isRescheduled(d)).toList()
                    : allBookings.where((d) => d['status'] == _filter).toList();

        // Apply search — use external searchQuery prop if provided, else internal
        final activeQuery = widget.searchQuery.isNotEmpty ? widget.searchQuery : _searchQuery;
        final filtered = activeQuery.isEmpty
            ? afterFilter
            : afterFilter.where((d) {
                final plate = (d['plate'] as String? ?? '').toLowerCase();
                final customer = (d['customerName'] as String? ?? '').toLowerCase();
                final svcs = ((d['services'] as List?) ?? []).join(' ').toLowerCase();
                final date = (d['preferredDate'] as String? ?? '').toLowerCase();
                return plate.contains(activeQuery) ||
                    customer.contains(activeQuery) ||
                    svcs.contains(activeQuery) ||
                    date.contains(activeQuery);
              }).toList();

        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              _statChip('Total', '$total', _blue, Icons.calendar_today_outlined, 'all'),
              const SizedBox(width: 6),
              _statChip('Approved', '$approved', const Color(0xFF38a169), Icons.check_circle_outline, 'Approved'),
              const SizedBox(width: 6),
              _statChip('Resched', '$rescheduled', _blue, Icons.history, 'Rescheduled'),
              const SizedBox(width: 6),
              _statChip('Cancelled', '$cancelled', _red, Icons.cancel_outlined, 'Dismissed'),
              const SizedBox(width: 6),
              _statChip('Pending', '$pending', const Color(0xFFd69e2e), Icons.access_time_outlined, 'Pending'),
            ]),
          ),
          Expanded(
            child: filtered.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.event_busy_outlined, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  const Text('No bookings found.', style: TextStyle(color: Color(0xFF718096), fontSize: 13)),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _buildCard(filtered[i]['docId'] as String, filtered[i]),
                ),
          ),
        ]);
      },
    );
  }

  bool _isRescheduled(Map<String, dynamic> data) {
    final previousDate = data['previousDate'] as String? ?? '';
    final preferredDate = data['preferredDate'] as String? ?? '';
    return previousDate.isNotEmpty && previousDate != preferredDate;
  }

  Widget _buildCard(String docId, Map<String, dynamic> data) {
    final plate = data['plate'] as String? ?? '—';
    final customerName = data['customerName'] as String? ?? '—';
    final services = (data['services'] as List?)?.join(', ') ?? '—';
    final preferredDate = data['preferredDate'] as String? ?? '';
    final preferredTime = data['preferredTime'] as String? ?? '—';
    final previousDate = data['previousDate'] as String? ?? '';
    final isRescheduled = previousDate.isNotEmpty && previousDate != preferredDate;
    final status = data['status'] as String? ?? '';
    final isApproved = status == 'Approved';
    final isPending = status == 'Pending';

    Color statusColor;
    String statusLabel;
    if (isRescheduled && isApproved) {
      statusColor = _blue;
      statusLabel = 'Rescheduled';
    } else if (isPending) {
      statusColor = const Color(0xFFd69e2e);
      statusLabel = 'Pending';
    } else if (isApproved) {
      statusColor = const Color(0xFF38a169);
      statusLabel = 'Approved';
    } else {
      statusColor = const Color(0xFF718096);
      statusLabel = 'Cancelled';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header: plate + status badge
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plate, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1a202c))),
            const SizedBox(height: 2),
            Text(customerName, style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568))),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
          ),
        ]),
        const SizedBox(height: 10),
        // Services
        Text(services, style: const TextStyle(fontSize: 12, color: Color(0xFF718096)), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 10),
        // Date and time
        Row(children: [
          const Icon(Icons.calendar_today_outlined, size: 13, color: Color(0xFF718096)),
          const SizedBox(width: 5),
          Text(_formatDate(preferredDate), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
          const SizedBox(width: 12),
          const Icon(Icons.access_time_outlined, size: 13, color: Color(0xFF718096)),
          const SizedBox(width: 5),
          Text(preferredTime, style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568))),
        ]),
        // Reschedule note
        if (isRescheduled) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF6E05E)),
            ),
            child: Row(children: [
              const Icon(Icons.history, size: 12, color: Color(0xFF92400E)),
              const SizedBox(width: 6),
              Expanded(child: Text(
                'Rescheduled from ${_formatDate(previousDate)}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF92400E)),
              )),
            ]),
          ),
        ],
        // Actions for Pending bookings
        if (isPending) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ElevatedButton.icon(
              onPressed: () => _approveBooking(docId, plate),
              icon: const Icon(Icons.check, size: 14),
              label: const Text('Approve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38a169), foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _dismissBooking(docId, plate),
              icon: const Icon(Icons.close, size: 14, color: Colors.red),
              label: const Text('Dismiss', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE8001C)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            )),
          ]),
        ],
        // Actions for Approved bookings
        if (isApproved) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ElevatedButton.icon(
              onPressed: () => _startService(docId, data),
              icon: const Icon(Icons.play_arrow, size: 14),
              label: const Text('Start Service', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38a169), foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            )),
            const SizedBox(width: 8),
            SizedBox(width: 38, height: 38, child: IconButton(
              onPressed: () => _showRescheduleModal(docId, data),
              icon: const Icon(Icons.history, size: 18, color: Color(0xFF003087)),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFEBF8FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            )),
            const SizedBox(width: 8),
            SizedBox(width: 38, height: 38, child: IconButton(
              onPressed: () => _dismissBooking(docId, plate),
              icon: const Icon(Icons.close, size: 18, color: Colors.red),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFFFF5F5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            )),
          ]),
        ],
      ]),
    );
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '—';
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return dateStr;
    return '${_months[m - 1]} $d, $y';
  }

  void _approveBooking(String docId, String plate) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Booking'),
        content: Text('Approve service booking for $plate?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseFirestore.instance.collection('service_bookings').doc(docId).update({'status': 'Approved'});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Booking approved for $plate'),
                  backgroundColor: const Color(0xFF38a169),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
              }
            },
            child: const Text('Approve', style: TextStyle(color: Color(0xFF38a169))),
          ),
        ],
      ),
    );
  }

  void _startService(String docId, Map<String, dynamic> data) async {
    final plate = data['plate'] as String? ?? '';
    final services = data['services'] as List? ?? [];
    final preferredDate = data['preferredDate'] as String? ?? '';
    
    // Update booking status to "In Progress"
    await FirebaseFirestore.instance.collection('service_bookings').doc(docId).update({'status': 'In Progress'});
    
    if (mounted) {
      // Navigate to Vehicle Maintenance with booking data auto-filled
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => AdminVehicleMaintenance(bookingData: {
          'bookingId': docId,
          'plate': plate,
          'services': services,
          'preferredDate': preferredDate,
        }),
      ));
    }
  }

  void _dismissBooking(String docId, String plate) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: Text('Cancel service booking for $plate?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('No')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final db = FirebaseFirestore.instance;
              // Fetch booking data to get customerId and date for notification
              final doc = await db.collection('service_bookings').doc(docId).get();
              final data = doc.data() ?? {};
              await db.collection('service_bookings').doc(docId).update({'status': 'Dismissed'});
              // Notify customer
              final customerId = data['customerId'] as String? ?? '';
              final date = data['preferredDate'] as String? ?? '';
              if (customerId.isNotEmpty) {
                await db.collection('notifications').add({
                  'title': '❌ Booking Cancelled',
                  'message': 'Your service booking for $plate on ${_formatDate(date)} has been cancelled by the admin.',
                  'type': 'warning',
                  'targetRole': 'customer', 'targetUid': customerId,
                  'createdAt': FieldValue.serverTimestamp(), 'readBy': <String, bool>{}, 'isRead': false,
                });
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Booking cancelled.'), backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating));
              }
            },
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showRescheduleModal(String docId, Map<String, dynamic> data) {
    final plate = data['plate'] as String? ?? '—';
    final currentDate = data['preferredDate'] as String? ?? '';
    final customerId = data['customerId'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _RescheduleSheet(
        docId: docId,
        plate: plate,
        currentDate: currentDate,
        customerId: customerId,
      ),
    );
  }
}

class _RescheduleSheet extends StatefulWidget {
  final String docId;
  final String plate;
  final String currentDate;
  final String customerId;

  const _RescheduleSheet({
    required this.docId,
    required this.plate,
    required this.currentDate,
    required this.customerId,
  });

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  static const _blue = Color(0xFF003087);
  static const _months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
  static const _maxPerDay = 5;

  late int _year;
  late int _month;
  String? _selectedDate;
  Map<String, int> _bookedDates = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _loadBookedDates();
  }

  Future<void> _loadBookedDates() async {
    final snap = await FirebaseFirestore.instance
        .collection('service_bookings')
        .where('status', whereIn: ['Approved', 'Pending'])
        .get();
    final counts = <String, int>{};
    for (final d in snap.docs) {
      final date = (d.data())['preferredDate'] as String? ?? '';
      if (date.isNotEmpty) counts[date] = (counts[date] ?? 0) + 1;
    }
    if (mounted) setState(() { _bookedDates = counts; _loading = false; });
  }

  void _navMonth(int dir) {
    setState(() {
      _month += dir;
      if (_month > 12) { _month = 1; _year++; }
      if (_month < 1) { _month = 12; _year--; }
    });
  }

  Future<void> _confirm() async {
    if (_selectedDate == null) return;
    final db = FirebaseFirestore.instance;

    await db.collection('service_bookings').doc(widget.docId).update({
      'preferredDate': _selectedDate,
      'previousDate': widget.currentDate,
      'rescheduledBy': 'admin',
      'rescheduledAt': FieldValue.serverTimestamp(),
    });

    // Notify customer
    if (widget.customerId.isNotEmpty) {
      await db.collection('notifications').add({
        'title': '📅 Booking Rescheduled',
        'message': 'Your booking for ${widget.plate} has been rescheduled from ${_fmt(widget.currentDate)} to ${_fmt(_selectedDate!)}.',
        'type': 'warning',
        'targetRole': 'customer',
        'targetUid': widget.customerId,
        'createdAt': FieldValue.serverTimestamp(),
        'readBy': <String, bool>{},
        'isRead': false,
      });
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Booking rescheduled to ${_fmt(_selectedDate!)}'),
        backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
    }
  }

  String _fmt(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    final m = int.tryParse(parts[1]) ?? 1;
    final d = int.tryParse(parts[2]) ?? 1;
    final y = int.tryParse(parts[0]) ?? 2026;
    return '${_months[m - 1]} $d, $y';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF003087), Color(0xFF001d52)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(children: [
              const Expanded(child: Text('Reschedule Booking',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.close, color: Colors.white, size: 16)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.plate, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1a202c))),
              if (widget.currentDate.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Current: ${_fmt(widget.currentDate)}', style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
              ],
              const SizedBox(height: 16),
              const Text('Select new date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
              const SizedBox(height: 10),

              // Month nav
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                GestureDetector(onTap: () => _navMonth(-1),
                  child: Container(width: 30, height: 30, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFe2e8f0)), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.chevron_left, size: 18, color: Color(0xFF4a5568)))),
                Text('${_months[_month - 1]} $_year', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                GestureDetector(onTap: () => _navMonth(1),
                  child: Container(width: 30, height: 30, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFe2e8f0)), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF4a5568)))),
              ]),
              const SizedBox(height: 10),

              // Calendar
              _loading
                  ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                  : _buildCalendar(),

              const SizedBox(height: 12),
              // Legend
              Wrap(spacing: 12, runSpacing: 4, children: [
                _legend(const Color(0xFF38a169), 'Available'),
                _legend(const Color(0xFFd97706), 'Full'),
                _legend(const Color(0xFFe2e8f0), 'Closed'),
                _legend(_blue, 'Current'),
              ]),

              const SizedBox(height: 16),
              // Selected date info
              if (_selectedDate != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF38a169))),
                  child: Text('📅 New Date: ${_fmt(_selectedDate!)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF38a169))),
                ),

              // Buttons
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Cancel'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: _selectedDate != null ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    disabledBackgroundColor: _blue.withOpacity(0.4),
                  ),
                  child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w700)),
                )),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
    ]);
  }

  Widget _buildCalendar() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDay = DateTime(_year, _month, 1);
    final firstWeekday = firstDay.weekday % 7;
    final daysInMonth = DateTime(_year, _month + 1, 0).day;

    final dow = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
    final cells = <Widget>[];

    for (final d in dow) {
      cells.add(Center(child: Text(d, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFa0aec0)))));
    }

    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }

    for (int d = 1; d <= daysInMonth; d++) {
      final dt = DateTime(_year, _month, d);
      final key = '$_year-${_month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      final isPast = dt.isBefore(today);
      final isSunday = dt.weekday == 7;
      final isCurrent = key == widget.currentDate;
      final isSelected = key == _selectedDate;
      final bookings = _bookedDates[key] ?? 0;
      final isFull = bookings >= _maxPerDay;
      final isDisabled = isPast || isSunday || isFull;

      Color bg;
      Color textColor;
      BoxBorder? border;
      if (isSelected) {
        bg = _blue;
        textColor = Colors.white;
      } else if (isCurrent && !isPast) {
        bg = const Color(0xFFEBF8FF);
        textColor = _blue;
        border = Border.all(color: _blue, width: 2);
      } else if (isPast || isSunday) {
        bg = const Color(0xFFF1F5F9);
        textColor = const Color(0xFFcbd5e0);
      } else if (isFull) {
        bg = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF92400E);
      } else {
        bg = const Color(0xFFF0FDF4);
        textColor = const Color(0xFF1a202c);
      }

      cells.add(GestureDetector(
        onTap: isDisabled ? null : () => setState(() => _selectedDate = key),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: border,
            boxShadow: isSelected ? [BoxShadow(color: _blue.withOpacity(0.3), blurRadius: 6)] : null,
          ),
          child: Center(child: Text('$d', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor))),
        ),
      ));
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      childAspectRatio: 1.2,
      children: cells,
    );
  }
}
