import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'customer_book_service.dart';

class CustomerMyBookings extends StatefulWidget {
  final bool embedded;
  const CustomerMyBookings({super.key, this.embedded = false});

  @override
  State<CustomerMyBookings> createState() => _CustomerMyBookingsState();
}

class _CustomerMyBookingsState extends State<CustomerMyBookings> {
  static const _red  = Color(0xFFE8001C);
  static const _blue = Color(0xFF003087);

  String _statusFilter = 'Approved'; // default: show Approved; tap chip to filter by Rescheduled/Cancelled, tap again to reset

  static const _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ];

  static const _monthsShort = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  String _fmtDate(String dateStr) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return '${_monthsShort[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _fmtDateLong(String dateStr) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  // ── Stat chip ─────────────────────────────────────────────────
  Widget _statChip(String label, String value, Color color, IconData icon, String filter) {
    final isActive = _statusFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _statusFilter = _statusFilter == filter ? 'Approved' : filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isActive ? color : Colors.transparent, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
          child: Column(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
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

  // ── Status helpers (mirrors website) ──────────────────────────
  _StatusStyle _statusStyle(Map<String, dynamic> data) {
    final status = (data['status'] as String? ?? 'Pending').toLowerCase();
    final previousDate = data['previousDate'] as String? ?? '';
    final date = data['preferredDate'] as String? ?? '';
    final isRescheduled = previousDate.isNotEmpty && previousDate != date;

    if (isRescheduled && status == 'approved') {
      return _StatusStyle('Rescheduled', const Color(0xFF003087),
          const Color(0xFFEBF4FF), Icons.update_outlined);
    }
    switch (status) {
      case 'approved':
        return _StatusStyle('Approved', const Color(0xFF38a169),
            const Color(0xFFF0FFF4), Icons.check_circle_outline);
      case 'completed':
        return _StatusStyle('Completed', const Color(0xFF003087),
            const Color(0xFFEBF4FF), Icons.task_alt_outlined);
      case 'cancelled':
      case 'rejected':
        return _StatusStyle('Cancelled', const Color(0xFFE8001C),
            const Color(0xFFFFF5F5), Icons.cancel_outlined);
      default:
        return _StatusStyle('Pending', const Color(0xFFdd6b20),
            const Color(0xFFFFFAF0), Icons.schedule_outlined);
    }
  }

  // ── Card ──────────────────────────────────────────────────────
  Widget _bookingCard(Map<String, dynamic> data) {
    final plate = data['plate'] as String? ?? '—';
    final vehicleDesc = data['vehicleDesc'] as String? ?? '';
    final date = data['preferredDate'] as String? ?? '';
    final time = data['preferredTime'] as String? ?? '';
    final ss = _statusStyle(data);
    final status = (data['status'] as String? ?? '').toLowerCase();

    return GestureDetector(
      onTap: () => _showModal(data),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFe2e8f0)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Card header ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(plate, style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF1a202c))),
                if (vehicleDesc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(vehicleDesc, style: const TextStyle(
                      fontSize: 12, color: Color(0xFF718096))),
                ],
              ])),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: ss.bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(ss.label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: ss.color)),
              ),
            ]),
          ),

          // ── Meta row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(children: [
              Icon(Icons.calendar_today_outlined,
                  size: 13, color: const Color(0xFF718096)),
              const SizedBox(width: 5),
              Text(date.isNotEmpty ? _fmtDate(date) : '—',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF718096))),
              if (time.isNotEmpty) ...[
                const SizedBox(width: 14),
                Icon(Icons.access_time_outlined,
                    size: 13, color: const Color(0xFF718096)),
                const SizedBox(width: 5),
                Text(time, style: const TextStyle(
                    fontSize: 11, color: Color(0xFF718096))),
              ],
            ]),
          ),

          // ── Footer ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
              border: Border(top: BorderSide(color: Color(0xFFF0F4F8))),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('View details',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE8001C))),
                Icon(Icons.chevron_right, size: 16, color: Color(0xFFE8001C)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Cancel booking ────────────────────────────────────────────
  Future<void> _cancelBooking(BuildContext ctx, Map<String, dynamic> data) async {
    final plate = data['plate'] as String? ?? '—';
    final docId = data['docId'] as String? ?? '';
    if (docId.isEmpty) return;

    String? reason;
    bool confirmed = false;

    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Red header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE31E24), Color(0xFFC41E3A)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cancel_outlined, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Cancel Booking',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('Plate: $plate',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
                GestureDetector(
                  onTap: () => Navigator.pop(sheetCtx),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ]),
            ),

            // ── Body ──
            Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Warning message
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE8001C).withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFE8001C), size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 13, color: Color(0xFF4a5568), height: 1.5),
                        children: [
                          const TextSpan(text: 'Are you sure you want to cancel your booking for '),
                          TextSpan(text: plate,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1a202c))),
                          const TextSpan(text: '? This action cannot be undone.'),
                        ],
                      ),
                    )),
                  ]),
                ),
                const SizedBox(height: 18),

                // Reason label
                RichText(text: const TextSpan(
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c)),
                  children: [
                    TextSpan(text: 'Reason for cancellation'),
                    TextSpan(text: ' *', style: TextStyle(color: Color(0xFFE8001C))),
                  ],
                )),
                const SizedBox(height: 10),

                // Dropdown
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFe2e8f0)),
                  ),
                  child: DropdownButtonFormField<String>(
                    value: reason,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF718096)),
                    decoration: const InputDecoration(
                      hintText: 'Select a reason...',
                      hintStyle: TextStyle(fontSize: 13, color: Color(0xFFa0aec0)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                    dropdownColor: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    items: const [
                      DropdownMenuItem(value: 'Schedule conflict',            child: Text('Schedule conflict')),
                      DropdownMenuItem(value: 'Vehicle issue resolved',       child: Text('Vehicle issue resolved')),
                      DropdownMenuItem(value: 'Found another service center', child: Text('Found another service center')),
                      DropdownMenuItem(value: 'Financial reasons',            child: Text('Financial reasons')),
                      DropdownMenuItem(value: 'Booked by mistake',            child: Text('Booked by mistake')),
                      DropdownMenuItem(value: 'Emergency / Personal reason',  child: Text('Emergency / Personal reason')),
                      DropdownMenuItem(value: 'Other',                        child: Text('Other')),
                    ],
                    onChanged: (v) => setSheet(() => reason = v),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Buttons ──
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFe2e8f0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('No, Keep It',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF718096))),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(
                    onPressed: () {
                      if (reason == null || reason!.isEmpty) {
                        setSheet(() {}); // trigger rebuild to show error
                        ScaffoldMessenger.of(sheetCtx).showSnackBar(
                          const SnackBar(
                            content: Text('Please select a reason for cancellation.'),
                            backgroundColor: Colors.redAccent,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      confirmed = true;
                      Navigator.pop(sheetCtx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8001C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                    ),
                    child: const Text('Yes, Cancel',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  )),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );

    if (!confirmed) return;

    final db = FirebaseFirestore.instance;
    final updateData = <String, dynamic>{
      'status': 'Cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': 'customer',
    };
    if (reason != null && reason!.isNotEmpty) {
      updateData['cancellationReason'] = reason;
    }
    await db.collection('service_bookings').doc(docId).update(updateData);

    final customerName = data['customerName'] as String? ?? 'Customer';
    final date = data['preferredDate'] as String? ?? '';
    final reasonSuffix = (reason != null && reason!.isNotEmpty) ? ' Reason: $reason' : '';
    await db.collection('notifications').add({
      'title': '❌ Booking Cancelled by Customer',
      'message': '$customerName cancelled their booking for $plate on ${date.isNotEmpty ? _fmtDateLong(date) : date}.$reasonSuffix',
      'type': 'warning',
      'targetRole': 'admin', 'targetUid': '',
      'createdAt': FieldValue.serverTimestamp(), 'readBy': <String, bool>{}, 'isRead': false,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text('Booking cancelled successfully.'),
        ]),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  // ── Modal ─────────────────────────────────────────────────────
  void _showModal(Map<String, dynamic> data) {
    final plate = data['plate'] as String? ?? '—';
    final vehicleDesc = data['vehicleDesc'] as String? ?? '';
    final services =
        (data['services'] as List<dynamic>?)?.cast<String>() ?? [];
    final date = data['preferredDate'] as String? ?? '';
    final time = data['preferredTime'] as String? ?? '';
    final notes = (data['notes'] as String? ?? '').trim();
    final previousDate = data['previousDate'] as String? ?? '';
    final isRescheduled =
        previousDate.isNotEmpty && previousDate != date;
    final ss = _statusStyle(data);
    final status = (data['status'] as String? ?? '').toLowerCase();
    final canCancel = status == 'pending' || status == 'approved';
    final docId = data['docId'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F8FA),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            // ── Modal header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                color: _red,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(plate, style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                    if (vehicleDesc.isNotEmpty)
                      Text(vehicleDesc, style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                  ])),
                ]),
              ]),
            ),

            // ── Modal body ──
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10)],
                  ),
                  child: Column(children: [
                    _detailRow(Icons.calendar_today_outlined,
                        'Preferred Date',
                        date.isNotEmpty ? _fmtDateLong(date) : '—',
                        const Color(0xFF003087)),
                    _divider(),
                    _detailRow(Icons.access_time_outlined,
                        'Preferred Time',
                        time.isNotEmpty ? time : '—',
                        const Color(0xFF003087)),
                    _divider(),
                    _detailRow(Icons.build_outlined, 'Services',
                        services.isNotEmpty
                            ? services.join(', ')
                            : '—',
                        _red),
                    _divider(),
                    _detailRow(Icons.info_outline, 'Status',
                        ss.label, ss.color),
                    // Show cancellation reason if cancelled
                    if ((status == 'cancelled' || status == 'rejected') &&
                        (data['cancellationReason'] as String? ?? '').trim().isNotEmpty) ...[
                      _divider(),
                      _detailRow(Icons.cancel_outlined, 'Cancellation Reason',
                          (data['cancellationReason'] as String).trim(),
                          const Color(0xFFE8001C)),
                    ],
                    if (notes.isNotEmpty) ...[
                      _divider(),
                      _detailRow(Icons.notes_outlined, 'Notes',
                          notes, const Color(0xFF718096)),
                    ],
                    if (isRescheduled) ...[
                      _divider(),
                      _detailRow(Icons.update_outlined,
                          'Rescheduled From',
                          '${_fmtDateLong(previousDate)} → ${_fmtDateLong(date)}',
                          const Color(0xFF92400E)),
                    ],
                  ]),
                ),
              ),
            ),
            // ── Cancel button (only for Pending / Approved) ──
            if (canCancel && docId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context); // close modal first
                      await _cancelBooking(context, data);
                    },
                    icon: const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFF718096)),
                    label: const Text('Cancel Booking',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF718096))),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFe2e8f0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _detailRow(
      IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 12),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(label, style: const TextStyle(
              fontSize: 11, color: Color(0xFF718096))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1a202c))),
        ])),
      ]),
    );
  }

  Widget _divider() =>
      const Divider(height: 1, indent: 62, endIndent: 12);

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        automaticallyImplyLeading: false,
        title: const Text('My Bookings',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CustomerBookService())),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: Color(0xFFE8001C), size: 16),
                SizedBox(width: 4),
                Text('Book Service',
                    style: TextStyle(color: Color(0xFFE8001C), fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
      ),
      // Wait for Firebase Auth to be ready before querying
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnap) {
          if (authSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final uid = authSnap.data?.uid ?? '';
          if (uid.isEmpty) {
            return const Center(
              child: Text('Please sign in to view your bookings.',
                  style: TextStyle(color: Color(0xFF718096))));
          }
          return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('service_bookings')
            .where('customerId', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting
              && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            // Common cause: missing Firestore index or permission denied
            final err = snapshot.error.toString();
            final isIndex = err.contains('index') || err.contains('FAILED_PRECONDITION');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(isIndex ? Icons.storage_outlined : Icons.error_outline,
                      size: 40, color: const Color(0xFF718096)),
                  const SizedBox(height: 12),
                  Text(
                    isIndex
                        ? 'A Firestore index is required.\nPlease check the debug console for a link to create it.'
                        : 'Unable to load bookings.\nPlease check your connection and try again.',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF718096)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(err,
                    style: const TextStyle(fontSize: 10, color: Color(0xFFa0aec0)),
                    textAlign: TextAlign.center),
                ]),
              ),
            );
          }

          final allDocs = snapshot.data?.docs ?? [];

          // Exclude "In Progress" and "Completed" bookings
          final docs = allDocs.where((doc) {
            final status = ((doc.data() as Map<String, dynamic>)['status'] as String? ?? '').toLowerCase();
            return status != 'in progress' && status != 'completed';
          }).toList();

          docs.sort((a, b) {
            final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

          // Count per status for stat chips
          int countApproved = 0, countRescheduled = 0, countCancelled = 0;
          for (final doc in docs) {
            final d = doc.data() as Map<String, dynamic>;
            final status = (d['status'] as String? ?? '').toLowerCase();
            final prevDate = d['previousDate'] as String? ?? '';
            final prefDate = d['preferredDate'] as String? ?? '';
            final isResched = prevDate.isNotEmpty && prevDate != prefDate;
            if (status == 'cancelled' || status == 'rejected') {
              countCancelled++;
            } else if (isResched && status == 'approved') {
              countRescheduled++;
            } else if (status == 'approved') {
              countApproved++;
            }
          }

          // Apply status filter — Approved is the default view
          final filteredDocs = docs.where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final status = (d['status'] as String? ?? '').toLowerCase();
            final prevDate = d['previousDate'] as String? ?? '';
            final prefDate = d['preferredDate'] as String? ?? '';
            final isResched = prevDate.isNotEmpty && prevDate != prefDate;
            switch (_statusFilter) {
              case 'Approved':    return status == 'approved' && !isResched;
              case 'Rescheduled': return status == 'approved' && isResched;
              case 'Cancelled':   return status == 'cancelled' || status == 'rejected';
              default:            return status == 'approved' && !isResched; // fallback to Approved
            }
          }).toList();

          if (docs.isEmpty) {
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  _statChip('Approved',   '$countApproved',  const Color(0xFF38a169),      Icons.check_circle_outline,    'Approved'),
                  const SizedBox(width: 6),
                  _statChip('Resched',    '$countRescheduled', _blue,                      Icons.update_outlined,         'Rescheduled'),
                  const SizedBox(width: 6),
                  _statChip('Cancelled',  '$countCancelled', _red,                         Icons.cancel_outlined,         'Cancelled'),
                ]),
              ),
              Expanded(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.calendar_month_outlined, size: 52, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    const Text('No bookings yet.', style: TextStyle(fontSize: 14, color: Color(0xFF718096))),
                    const SizedBox(height: 4),
                    const Text('Book a service to get started.', style: TextStyle(fontSize: 12, color: Color(0xFFa0aec0))),
                  ]),
                ),
              ),
            ]);
          }

          return Column(children: [
            // ── Stat chips ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                _statChip('Approved',  '$countApproved',    const Color(0xFF38a169), Icons.check_circle_outline,    'Approved'),
                const SizedBox(width: 6),
                _statChip('Resched',   '$countRescheduled', _blue,                   Icons.update_outlined,         'Rescheduled'),
                const SizedBox(width: 6),
                _statChip('Cancelled', '$countCancelled',   _red,                    Icons.cancel_outlined,         'Cancelled'),
              ]),
            ),
            // ── Filtered list ──
            Expanded(
              child: filteredDocs.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.calendar_month_outlined, size: 44, color: Colors.grey.shade300),
                        const SizedBox(height: 10),
                        Text(
                          _statusFilter == 'Approved' ? 'No approved bookings.'
                          : _statusFilter == 'Rescheduled' ? 'No rescheduled bookings.'
                          : 'No cancelled bookings.',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF718096))),
                      ]),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredDocs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final data = {
                          ...filteredDocs[i].data() as Map<String, dynamic>,
                          'docId': filteredDocs[i].id,
                        };
                        return _bookingCard(data);
                      },
                    ),
            ),
          ]);
        },
      );  // inner StreamBuilder<QuerySnapshot>
        },  // outer StreamBuilder<User?> builder
      ),    // outer StreamBuilder<User?>
    );      // Scaffold
  }         // build
}

// ── Helper model ─────────────────────────────────────────────
class _StatusStyle {
  final String label;
  final Color color;
  final Color bg;
  final IconData icon;
  const _StatusStyle(this.label, this.color, this.bg, this.icon);
}
