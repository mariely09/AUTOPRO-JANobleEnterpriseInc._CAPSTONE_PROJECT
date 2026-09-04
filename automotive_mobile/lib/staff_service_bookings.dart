import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'staff_maintenance.dart';

class StaffServiceBookingsBody extends StatefulWidget {
  final String searchQuery;
  const StaffServiceBookingsBody({super.key, this.searchQuery = ''});

  @override
  State<StaffServiceBookingsBody> createState() => _StaffServiceBookingsBodyState();
}

class _StaffServiceBookingsBodyState extends State<StaffServiceBookingsBody> {
  static const _blue = Color(0xFF003087);
  static const _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ];

  String _filter = 'all'; // 'all', 'Approved', 'Rescheduled', 'Dismissed'

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
            color: isActive ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isActive ? color : Colors.transparent, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
          ),
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
          return status == 'Approved' || status == 'Cancelled';
        }).toList();

        // Auto-cancel past-due bookings (fire-and-forget)
        _autoCancelPastDue(allDocs);

        final approved    = allBookings.where((d) => d['status'] == 'Approved' && !_isRescheduled(d)).length;
        final rescheduled = allBookings.where((d) => d['status'] == 'Approved' && _isRescheduled(d)).length;
        final cancelled   = allBookings.where((d) => d['status'] == 'Cancelled').length;
        final total       = allBookings.length;

        final afterFilter = _filter == 'all'
            ? allBookings
            : _filter == 'Rescheduled'
                ? allBookings.where((d) => d['status'] == 'Approved' && _isRescheduled(d)).toList()
                : _filter == 'Cancelled'
                    ? allBookings.where((d) => d['status'] == 'Cancelled').toList()
                    : allBookings.where((d) => d['status'] == 'Approved' && !_isRescheduled(d)).toList();

        final q = widget.searchQuery.toLowerCase();
        final filtered = q.isEmpty
            ? afterFilter
            : afterFilter.where((d) {
                final plate    = (d['plate']        as String? ?? '').toLowerCase();
                final customer = (d['customerName'] as String? ?? '').toLowerCase();
                final svcs     = ((d['services'] as List?) ?? []).join(' ').toLowerCase();
                final date     = (d['preferredDate'] as String? ?? '').toLowerCase();
                return plate.contains(q) || customer.contains(q) ||
                    svcs.contains(q) || date.contains(q);
              }).toList();

        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              _statChip('Approved',  '$approved',   const Color(0xFF38a169),   Icons.check_circle_outline,    'Approved'),
              const SizedBox(width: 6),
              _statChip('Resched',   '$rescheduled', _blue,                    Icons.history,                 'Rescheduled'),
              const SizedBox(width: 6),
              _statChip('Cancelled', '$cancelled',  const Color(0xFFE8001C),   Icons.cancel_outlined,         'Cancelled'),
            ]),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.event_busy_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    const Text('No bookings found.',
                        style: TextStyle(color: Color(0xFF718096), fontSize: 13)),
                  ]))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) =>
                        _buildCard(filtered[i]['docId'] as String, filtered[i]),
                  ),
          ),
        ]);
      },
    );
  }

  bool _isRescheduled(Map<String, dynamic> data) {
    final prev = data['previousDate'] as String? ?? '';
    final pref = data['preferredDate'] as String? ?? '';
    return prev.isNotEmpty && prev != pref;
  }

  /// Auto-cancels any Approved booking whose preferredDate is in the past,
  /// or is today and the current time is at or after 5:00 PM.
  void _autoCancelPastDue(List<QueryDocumentSnapshot> docs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isPastFivePm = now.hour >= 17;
    final db = FirebaseFirestore.instance;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if ((data['status'] as String? ?? '') != 'Approved') continue;
      final prefDate = data['preferredDate'] as String? ?? '';
      if (prefDate.isEmpty) continue;
      final prefDateTime = DateTime.tryParse(prefDate);
      if (prefDateTime == null) continue;

      final isPastDay  = prefDateTime.isBefore(today);
      final isToday5pm = prefDateTime.isAtSameMomentAs(today) && isPastFivePm;
      if (!isPastDay && !isToday5pm) continue;

      final reason = isPastDay
          ? 'No-show / Service date passed'
          : 'No-show / Service not started by closing time (5:00 PM)';

      db.collection('service_bookings').doc(doc.id).update({
        'status': 'Cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': 'system',
        'cancellationReason': reason,
      }).then((_) {
        final customerId = data['customerId'] as String? ?? '';
        final plate      = data['plate']      as String? ?? '';
        final custName   = data['customerName'] as String? ?? 'Customer';
        final timeLabel  = (data['preferredTime'] as String? ?? '').isNotEmpty
            ? ' at ${data['preferredTime']}' : '';
        final dateLabel  = _formatDate(prefDate);

        if (customerId.isNotEmpty) {
          final msg = isPastDay
              ? 'Your booking for $plate on $dateLabel was automatically cancelled because the scheduled date has passed.'
              : 'Your booking for $plate on $dateLabel$timeLabel was automatically cancelled because the service was not started by 5:00 PM.';
          db.collection('notifications').add({
            'title':   '❌ Booking Auto-Cancelled',
            'message': msg,
            'type':    'warning',
            'targetRole': '', 'targetUid': customerId,
            'createdAt': FieldValue.serverTimestamp(),
            'readBy': <String, bool>{}, 'isRead': false,
          });
        }

        final adminStaffMsg = "$custName's booking for $plate on $dateLabel$timeLabel "
            'was auto-cancelled (no-show / not started by 5:00 PM).';

        // ── Notify admin ──
        db.collection('notifications').add({
          'title':   '🔔 Booking Auto-Cancelled',
          'message': adminStaffMsg,
          'type':    'warning',
          'targetRole': 'admin', 'targetUid': '',
          'createdAt': FieldValue.serverTimestamp(),
          'readBy': <String, bool>{}, 'isRead': false,
        });

        // ── Notify staff ──
        db.collection('notifications').add({
          'title':   '🔔 Booking Auto-Cancelled',
          'message': adminStaffMsg,
          'type':    'warning',
          'targetRole': 'staff', 'targetUid': '',
          'createdAt': FieldValue.serverTimestamp(),
          'readBy': <String, bool>{}, 'isRead': false,
        });
      }).catchError((_) {});
    }
  }

  Widget _buildCard(String docId, Map<String, dynamic> data) {
    final plate        = data['plate']        as String? ?? '—';
    final customerName = data['customerName'] as String? ?? '—';
    final services     = (data['services'] as List?)?.join(', ') ?? '—';
    final preferredDate = data['preferredDate'] as String? ?? '';
    final preferredTime = data['preferredTime'] as String? ?? '—';
    final previousDate  = data['previousDate'] as String? ?? '';
    final isRescheduled = previousDate.isNotEmpty && previousDate != preferredDate;
    final status        = data['status'] as String? ?? '';
    final isApproved    = status == 'Approved';

    Color statusColor;
    String statusLabel;
    if (isRescheduled && isApproved) {
      statusColor = _blue;
      statusLabel = 'Rescheduled';
    } else if (isApproved) {
      statusColor = const Color(0xFF38a169);
      statusLabel = 'Approved';
    } else {
      statusColor = const Color(0xFFE8001C);
      statusLabel = 'Cancelled';
    }

    return GestureDetector(
      onTap: () => _showBookingDetails(docId, data),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(plate, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1a202c))),
              const SizedBox(height: 2),
              Text(customerName, style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568))),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(statusLabel,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(services,
              style: const TextStyle(fontSize: 12, color: Color(0xFF718096)),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 13, color: Color(0xFF718096)),
            const SizedBox(width: 5),
            Text(_formatDate(preferredDate),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
            const SizedBox(width: 12),
            const Icon(Icons.access_time_outlined, size: 13, color: Color(0xFF718096)),
            const SizedBox(width: 5),
            Text(preferredTime, style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568))),
          ]),
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
                Expanded(child: Text('Rescheduled from ${_formatDate(previousDate)}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF92400E)))),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('Tap to view details', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 14, color: Colors.grey.shade400),
          ]),
        ]),
      ),
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

  // ── View Details ────────────────────────────────────────────────────────────

  void _showBookingDetails(String docId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _StaffBookingDetailsSheet(
        docId: docId,
        data: data,
        onStartService: () {
          Navigator.pop(context);
          _startService(docId, data);
        },
        onReschedule: () {
          Navigator.pop(context);
          _showRescheduleModal(docId, data);
        },
        onDismiss: () {
          Navigator.pop(context);
          _dismissBooking(docId, data['plate'] as String? ?? '—');
        },
        formatDate: _formatDate,
      ),
    );
  }

  void _startService(String docId, Map<String, dynamic> data) async {
    final plate         = data['plate']         as String? ?? '';
    final services      = data['services']      as List?   ?? [];
    final preferredDate = data['preferredDate'] as String? ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.play_circle_outline, color: Color(0xFF38a169), size: 22),
          SizedBox(width: 8),
          Text('Start Service', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Are you sure you want to start the service for $plate?',
              style: const TextStyle(fontSize: 14, color: Color(0xFF1a202c))),
          const SizedBox(height: 6),
          const Text('This will mark the booking as Under Maintenance and open the maintenance form.',
              style: TextStyle(fontSize: 12, color: Color(0xFF718096))),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38a169),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes, Start'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await FirebaseFirestore.instance
        .collection('service_bookings')
        .doc(docId)
        .update({'status': 'Under Maintenance'});

    // Notify customer — in-app
    final bSnap = await FirebaseFirestore.instance.collection('service_bookings').doc(docId).get();
    final bData = bSnap.data() ?? {};
    final customerId = bData['customerId'] as String? ?? '';
    if (customerId.isNotEmpty) {
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': '🔧 Vehicle Under Maintenance',
        'message': 'Your vehicle $plate is now under maintenance. We will notify you once the service is completed.',
        'type': 'info',
        'targetRole': '', 'targetUid': customerId,
        'createdAt': FieldValue.serverTimestamp(), 'readBy': <String, bool>{}, 'isRead': false,
      });
    }

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => StaffMaintenance(bookingData: {
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
        content: Text('Are you sure you want to cancel this booking for $plate?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('No')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final db = FirebaseFirestore.instance;
              final doc = await db.collection('service_bookings').doc(docId).get();
              final d   = doc.data() ?? {};
              // Mark as Cancelled (keep in database for records)
              await db.collection('service_bookings').doc(docId).update({
                'status': 'Cancelled',
                'cancelledAt': FieldValue.serverTimestamp(),
                'cancelledBy': 'staff',
              });
              final customerId = d['customerId'] as String? ?? '';
              final date       = d['preferredDate'] as String? ?? '';
              if (customerId.isNotEmpty) {
                await db.collection('notifications').add({
                  'title': '❌ Booking Cancelled',
                  'message': 'Your service booking for $plate on ${_formatDate(date)} has been cancelled.',
                  'type': 'warning',
                  'targetRole': '', 'targetUid': customerId,
                  'createdAt': FieldValue.serverTimestamp(),
                  'readBy': <String, bool>{}, 'isRead': false,
                });
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Booking cancelled.'),
                  backgroundColor: Colors.green,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _StaffRescheduleSheet(
        docId: docId,
        plate:       data['plate']         as String? ?? '—',
        currentDate: data['preferredDate'] as String? ?? '',
        currentTime: data['preferredTime'] as String? ?? '',
        customerId:  data['customerId']    as String? ?? '',
      ),
    );
  }
}

// ─── Staff Booking Details Sheet ─────────────────────────────────────────────

class _StaffBookingDetailsSheet extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback onStartService;
  final VoidCallback onReschedule;
  final VoidCallback onDismiss;
  final String Function(String) formatDate;

  static const _blue  = Color(0xFF003087);
  static const _green = Color(0xFF38a169);
  static const _red   = Color(0xFFE8001C);

  const _StaffBookingDetailsSheet({
    required this.docId,
    required this.data,
    required this.onStartService,
    required this.onReschedule,
    required this.onDismiss,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final plate         = data['plate']        as String? ?? '—';
    final customerName  = data['customerName'] as String? ?? '—';
    final services      = (data['services'] as List?)?.cast<String>() ?? [];
    final preferredDate = data['preferredDate'] as String? ?? '';
    final preferredTime = data['preferredTime'] as String? ?? '—';
    final previousDate  = data['previousDate'] as String? ?? '';
    final status        = data['status'] as String? ?? '';
    final isApproved    = status == 'Approved';
    final isRescheduled = previousDate.isNotEmpty && previousDate != preferredDate;
    final isCancelled   = status == 'Dismissed';

    Color statusColor;
    String statusLabel;
    if (isRescheduled && isApproved) {
      statusColor = _blue;  statusLabel = 'Rescheduled';
    } else if (isApproved) {
      statusColor = _green; statusLabel = 'Approved';
    } else {
      statusColor = _red; statusLabel = 'Cancelled';
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFE8001C), Color(0xFFa50014)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(children: [
              const Expanded(child: Text('Booking Details',
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
              // Plate + Status
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(plate, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF1a202c))),
                  const SizedBox(height: 2),
                  Text(customerName, style: const TextStyle(fontSize: 13, color: Color(0xFF4a5568))),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                ),
              ]),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFe2e8f0)),
              const SizedBox(height: 16),
              // Date & Time
              _infoRow(Icons.calendar_today_outlined, 'Date', formatDate(preferredDate)),
              const SizedBox(height: 10),
              _infoRow(Icons.access_time_outlined, 'Time', preferredTime),
              // Reschedule note
              if (isRescheduled) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF6E05E)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.history, size: 14, color: Color(0xFF92400E)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Rescheduled from ${formatDate(previousDate)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)))),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFe2e8f0)),
              const SizedBox(height: 16),
              // Services
              const Text('Services', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF4a5568))),
              const SizedBox(height: 8),
              if (services.isEmpty)
                const Text('—', style: TextStyle(fontSize: 13, color: Color(0xFF718096)))
              else
                Wrap(spacing: 6, runSpacing: 6,
                  children: services.map((s) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: const Color(0xFFEBF8FF), borderRadius: BorderRadius.circular(20)),
                    child: Text(s, style: const TextStyle(fontSize: 11, color: _blue, fontWeight: FontWeight.w600)),
                  )).toList()),
              const SizedBox(height: 20),
              // Action buttons — Approved only
              if (isApproved) ...[
                Builder(builder: (ctx) {
                  final now = DateTime.now();
                  final todayKey = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
                  final isToday = preferredDate == todayKey;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isToday ? onStartService : null,
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('Start Service', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green, foregroundColor: Colors.white,
                          disabledBackgroundColor: _green.withValues(alpha: 0.35),
                          disabledForegroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    if (!isToday) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.info_outline, size: 12, color: Color(0xFF718096)),
                        const SizedBox(width: 4),
                        Expanded(child: Text(
                          DateTime.tryParse(preferredDate)?.isBefore(DateTime.now()) == true
                              ? 'Scheduled date has passed — please reschedule.'
                              : 'Scheduled on ${formatDate(preferredDate)} — not yet available to start.',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
                        )),
                      ]),
                    ],
                  ]);
                }),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: onReschedule,
                    icon: const Icon(Icons.history, size: 15, color: _blue),
                    label: const Text('Reschedule', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _blue)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _blue),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close, size: 15, color: _red),
                    label: const Text('Cancel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  )),
                ]),
              ],
              if (isCancelled)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Close'),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: const Color(0xFF718096)),
      const SizedBox(width: 8),
      Text('$label: ', style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
    ]);
  }
}

// ─── Staff Reschedule Sheet ───────────────────────────────────────────────────

class _StaffRescheduleSheet extends StatefulWidget {
  final String docId;
  final String plate;
  final String currentDate;
  final String currentTime;
  final String customerId;

  const _StaffRescheduleSheet({
    required this.docId,
    required this.plate,
    required this.currentDate,
    required this.currentTime,
    required this.customerId,
  });

  @override
  State<_StaffRescheduleSheet> createState() => _StaffRescheduleSheetState();
}

class _StaffRescheduleSheetState extends State<_StaffRescheduleSheet> {
  static const _blue = Color(0xFF003087);
  static const _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ];
  static const _allTimeSlots = ['8:00 AM','9:00 AM','10:00 AM','11:00 AM','1:00 PM','2:00 PM','3:00 PM','4:00 PM'];
  static const _arriveByMap = {
    '8:00 AM': '7:45 AM', '9:00 AM': '8:45 AM', '10:00 AM': '9:45 AM', '11:00 AM': '10:45 AM',
    '1:00 PM': '12:45 PM', '2:00 PM': '1:45 PM', '3:00 PM': '2:45 PM', '4:00 PM': '3:45 PM',
  };

  late int _year;
  late int _month;
  String? _selectedDate;
  String? _selectedTime;
  Map<String, List<String>> _bookedDates = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year  = now.year;
    _month = now.month;
    _loadBookedDates();
  }

  Future<void> _loadBookedDates() async {
    final snap = await FirebaseFirestore.instance
        .collection('service_bookings')
        .where('status', whereIn: ['Approved'])
        .get();
    final slots = <String, List<String>>{};
    for (final d in snap.docs) {
      if (d.id == widget.docId) continue; // exclude self
      final date = d.data()['preferredDate'] as String? ?? '';
      final time = d.data()['preferredTime'] as String? ?? '';
      if (date.isNotEmpty && time.isNotEmpty) {
        slots.putIfAbsent(date, () => []);
        if (!slots[date]!.contains(time)) slots[date]!.add(time);
      }
    }
    if (mounted) setState(() { _bookedDates = slots; _loading = false; });
  }

  void _navMonth(int dir) {
    setState(() {
      _month += dir;
      if (_month > 12) { _month = 1;  _year++; }
      if (_month < 1)  { _month = 12; _year--; }
    });
  }

  Future<void> _confirm() async {
    if (_selectedDate == null || _selectedTime == null) return;
    final db = FirebaseFirestore.instance;
    await db.collection('service_bookings').doc(widget.docId).update({
      'preferredDate': _selectedDate,
      'preferredTime': _selectedTime,
      'previousDate':  widget.currentDate,
      'previousTime':  widget.currentTime,
      'rescheduledBy': 'staff',
      'rescheduledAt': FieldValue.serverTimestamp(),
    });
    if (widget.customerId.isNotEmpty) {
      await db.collection('notifications').add({
        'title':      '📅 Booking Rescheduled',
        'message':    'Your booking for ${widget.plate} has been rescheduled from ${_fmt(widget.currentDate)}${widget.currentTime.isNotEmpty ? ' at ${widget.currentTime}' : ''} to ${_fmt(_selectedDate!)} at $_selectedTime.',
        'type':       'warning',
        'targetRole': '',
        'targetUid':  widget.customerId,
        'createdAt':  FieldValue.serverTimestamp(),
        'readBy':     <String, bool>{},
        'isRead':     false,
      });
    }

    // Send reschedule email to customer (fire-and-forget)
    if (widget.customerId.isNotEmpty) {
      _sendRescheduleEmail(db, widget.customerId);
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Booking rescheduled to ${_fmt(_selectedDate!)} at $_selectedTime'),
        backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
    }
  }

  /// Looks up customer email + booking services, then calls Flask /api/send-reschedule-email.
  Future<void> _sendRescheduleEmail(FirebaseFirestore db, String customerId) async {
    const flaskBaseUrl = 'https://caltex-autopro.onrender.com';
    try {
      final userDoc = await db.collection('users').doc(customerId).get();
      final email   = userDoc.data()?['email'] as String? ?? '';
      final name    = userDoc.data()?['name']  as String? ?? '';
      if (email.isEmpty) return;

      final bDoc     = await db.collection('service_bookings').doc(widget.docId).get();
      final services = ((bDoc.data()?['services'] as List?) ?? []).join(', ');

      await http.post(
        Uri.parse('$flaskBaseUrl/api/send-reschedule-email'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'to_email': email,
          'to_name':  name,
          'plate':    widget.plate,
          'old_date': _fmt(widget.currentDate) + (widget.currentTime.isNotEmpty ? ' at ${widget.currentTime}' : ''),
          'new_date': _fmt(_selectedDate!) + ' at $_selectedTime',
          'services': services,
        }),
      );
    } catch (e) {
      debugPrint('❌ Reschedule email error: $e');
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
    final takenTimes = _selectedDate != null ? (_bookedDates[_selectedDate] ?? []) : <String>[];
    final canConfirm = _selectedDate != null && _selectedTime != null;

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
                Text(
                  'Current: ${_fmt(widget.currentDate)}${widget.currentTime.isNotEmpty ? ' at ${widget.currentTime}' : ''}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF718096)),
                ),
              ],
              const SizedBox(height: 16),
              const Text('1. Select new date',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF4a5568))),
              const SizedBox(height: 10),
              // Month nav
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                GestureDetector(onTap: () => _navMonth(-1),
                  child: Container(width: 30, height: 30,
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFe2e8f0)), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.chevron_left, size: 18, color: Color(0xFF4a5568)))),
                Text('${_months[_month - 1]} $_year',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                GestureDetector(onTap: () => _navMonth(1),
                  child: Container(width: 30, height: 30,
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFe2e8f0)), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF4a5568)))),
              ]),
              const SizedBox(height: 10),
              _loading
                  ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                  : _buildCalendar(),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 4, children: [
                _legend(const Color(0xFF38a169), 'Available'),
                _legend(const Color(0xFFd97706), 'Full'),
                _legend(_blue, 'Current'),
              ]),

              // ── Step 2: Time ──
              if (_selectedDate != null) ...[
                const SizedBox(height: 20),
                const Text('2. Select new time',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF4a5568))),
                const SizedBox(height: 4),
                const Text('Please arrive 15 minutes before your selected time.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _allTimeSlots.map((time) {
                    final isTaken = takenTimes.contains(time);
                    final isSelected = _selectedTime == time;
                    return GestureDetector(
                      onTap: isTaken ? null : () => setState(() => _selectedTime = time),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isTaken ? const Color(0xFFF1F5F9) : isSelected ? const Color(0xFFEBF8FF) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isTaken ? const Color(0xFFe2e8f0) : isSelected ? _blue : const Color(0xFFe2e8f0),
                            width: isSelected ? 2 : 1.5,
                          ),
                        ),
                        child: Text(time, style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: isTaken ? const Color(0xFFa0aec0) : isSelected ? _blue : const Color(0xFF4a5568),
                          decoration: isTaken ? TextDecoration.lineThrough : null,
                          decorationColor: const Color(0xFFa0aec0),
                        )),
                      ),
                    );
                  }).toList(),
                ),
                if (_selectedTime != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFC6F6D5)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.access_time, size: 13, color: Color(0xFF38A169)),
                      const SizedBox(width: 6),
                      Text('Customer arrives by: ${_arriveByMap[_selectedTime!] ?? _selectedTime!}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF276749), fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ],
              ],

              const SizedBox(height: 16),
              // Summary card
              if (canConfirm)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF38a169)),
                  ),
                  child: Column(children: [
                    Text('📅 ${_fmt(_selectedDate!)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF38a169))),
                    const SizedBox(height: 2),
                    Text('🕐 $_selectedTime',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF276749))),
                  ]),
                ),

              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Cancel'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: canConfirm ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    disabledBackgroundColor: _blue.withValues(alpha: 0.4),
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
    final now      = DateTime.now();
    final today    = DateTime(now.year, now.month, now.day);
    final firstDay = DateTime(_year, _month, 1);
    final firstWeekday = firstDay.weekday % 7;
    final daysInMonth  = DateTime(_year, _month + 1, 0).day;

    final dow   = ['SU','MO','TU','WE','TH','FR','SA'];
    final cells = <Widget>[];

    for (final d in dow) {
      cells.add(Center(child: Text(d,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFa0aec0)))));
    }
    for (int i = 0; i < firstWeekday; i++) { cells.add(const SizedBox.shrink()); }

    for (int d = 1; d <= daysInMonth; d++) {
      final dt  = DateTime(_year, _month, d);
      final key = '$_year-${_month.toString().padLeft(2,'0')}-${d.toString().padLeft(2,'0')}';
      final isPast      = dt.isBefore(today);
      final isCurrent   = key == widget.currentDate;
      final isSelected  = key == _selectedDate;
      final bookings    = _bookedDates[key] ?? [];
      final isFull      = bookings.length >= _allTimeSlots.length;
      final isDisabled  = isPast || isFull;

      Color bg; Color textColor; BoxBorder? border;
      if (isSelected) {
        bg = _blue; textColor = Colors.white;
      } else if (isCurrent && !isPast) {
        bg = const Color(0xFFEBF8FF); textColor = _blue;
        border = Border.all(color: _blue, width: 2);
      } else if (isPast) {
        bg = const Color(0xFFF1F5F9); textColor = const Color(0xFFcbd5e0);
      } else if (isFull) {
        bg = const Color(0xFFFEF3C7); textColor = const Color(0xFF92400E);
      } else {
        bg = const Color(0xFFF0FDF4); textColor = const Color(0xFF1a202c);
      }

      cells.add(GestureDetector(
        onTap: isDisabled ? null : () => setState(() {
          _selectedDate = key;
          _selectedTime = null; // reset time when date changes
        }),
        child: Container(
          decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(8), border: border,
            boxShadow: isSelected ? [BoxShadow(color: _blue.withValues(alpha: 0.3), blurRadius: 6)] : null,
          ),
          child: Center(child: Text('$d',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor))),
        ),
      ));
    }

    return GridView.count(
      crossAxisCount: 7, shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 1.2,
      children: cells,
    );
  }
}
