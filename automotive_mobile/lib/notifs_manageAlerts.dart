import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum ManageAlertsRole { customer, staff, admin }

class ManageAlertsScreen extends StatefulWidget {
  final ManageAlertsRole role;
  const ManageAlertsScreen({super.key, this.role = ManageAlertsRole.customer});

  @override
  State<ManageAlertsScreen> createState() => _ManageAlertsScreenState();
}

class _ManageAlertsScreenState extends State<ManageAlertsScreen> {
  static const _red   = Color(0xFFE8001C);
  static const _blue  = Color(0xFF003087);

  bool _loading = true;
  bool _saving  = false;

  // ── Notification channels ──────────────────────────────────
  bool _inAppEnabled = true;
  bool _emailEnabled = true;

  // ── Vehicle alert preferences ──────────────────────────────
  bool _pmsOverdue     = true;
  bool _pmsDueToday    = true;
  bool _pmsDueThisWeek = true;
  bool _pmsDueSoon     = true;

  // ── Service alert preferences (staff & admin) ──────────────
  bool _serviceUpdate = true;
  bool _newAssignment = true;

  // ── Inventory alert preferences (admin) ───────────────────
  bool _lowStock = true;

  // ── Booking alert preferences ──────────────────────────────
  bool _bookingConfirmed    = true;  // customer
  bool _bookingReminder     = true;  // customer
  bool _bookingStatusChange = true;  // customer
  bool _newBookingRequest   = true;  // staff & admin
  bool _bookingCancellation = true;  // staff & admin

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('settings').doc('alerts')
        .get();
    if (!mounted) return;
    final data = doc.data() ?? {};
    setState(() {
      // Channels
      _inAppEnabled = data['inAppEnabled'] as bool? ?? true;
      _emailEnabled = data['emailEnabled'] as bool? ?? true;
      // Vehicle
      _pmsOverdue     = data['pmsOverdue']     as bool? ?? true;
      _pmsDueToday    = data['pmsDueToday']    as bool? ?? true;
      _pmsDueThisWeek = data['pmsDueThisWeek'] as bool? ?? true;
      _pmsDueSoon     = data['pmsDueSoon']     as bool? ?? true;
      // Service
      _serviceUpdate  = data['serviceUpdate']  as bool? ?? true;
      _newAssignment  = data['newAssignment']  as bool? ?? true;
      // Inventory
      _lowStock       = data['lowStock']       as bool? ?? true;
      // Booking
      _bookingConfirmed    = data['bookingConfirmed']    as bool? ?? true;
      _bookingReminder     = data['bookingReminder']     as bool? ?? true;
      _bookingStatusChange = data['bookingStatusChange'] as bool? ?? true;
      _newBookingRequest   = data['newBookingRequest']   as bool? ?? true;
      _bookingCancellation = data['bookingCancellation'] as bool? ?? true;
      _loading = false;
    });
  }

  Future<void> _savePrefs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      final isStaffOrAdmin = widget.role == ManageAlertsRole.staff || widget.role == ManageAlertsRole.admin;
      final isAdmin        = widget.role == ManageAlertsRole.admin;
      final isCustomer     = widget.role == ManageAlertsRole.customer;

      final payload = <String, dynamic>{
        // Channels — all roles
        'inAppEnabled': _inAppEnabled,
        'emailEnabled': _emailEnabled,
        // Vehicle — all roles
        'pmsOverdue':     _pmsOverdue,
        'pmsDueToday':    _pmsDueToday,
        'pmsDueThisWeek': _pmsDueThisWeek,
        'pmsDueSoon':     _pmsDueSoon,
        // Service — staff & admin
        if (isStaffOrAdmin) 'serviceUpdate': _serviceUpdate,
        if (isStaffOrAdmin) 'newAssignment': _newAssignment,
        // Inventory — admin only
        if (isAdmin) 'lowStock': _lowStock,
        // Booking — customer
        if (isCustomer) 'bookingConfirmed':    _bookingConfirmed,
        if (isCustomer) 'bookingReminder':     _bookingReminder,
        if (isCustomer) 'bookingStatusChange': _bookingStatusChange,
        // Booking — staff & admin
        if (isStaffOrAdmin) 'newBookingRequest':   _newBookingRequest,
        if (isStaffOrAdmin) 'bookingCancellation': _bookingCancellation,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('settings').doc('alerts')
          .set(payload, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Alert preferences saved!'),
          ]),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStaffOrAdmin = widget.role == ManageAlertsRole.staff || widget.role == ManageAlertsRole.admin;
    final isAdmin        = widget.role == ManageAlertsRole.admin;
    final isCustomer     = widget.role == ManageAlertsRole.customer;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Manage Alerts',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _savePrefs,
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── Notification Channels (all roles) ─────────────────
                _sectionLabel('NOTIFICATION CHANNELS'),
                const SizedBox(height: 4),
                Text(
                  'Choose how you want to receive notifications.',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
                ),
                const SizedBox(height: 8),
                _alertCard([
                  _channelTile(
                    icon: Icons.notifications_active_outlined,
                    color: _red,
                    title: 'In-App Notifications',
                    sub: 'Show alerts inside the app in real time',
                    value: _inAppEnabled,
                    onChanged: (v) => setState(() => _inAppEnabled = v),
                  ),
                  _channelTile(
                    icon: Icons.email_outlined,
                    color: _blue,
                    title: 'Email Notifications',
                    sub: 'Send alerts to your registered email address',
                    value: _emailEnabled,
                    onChanged: (v) => setState(() => _emailEnabled = v),
                    isLast: true,
                  ),
                ]),

                // ── Vehicle Alerts (all roles) ─────────────────────────
                const SizedBox(height: 20),
                _sectionLabel('VEHICLE ALERTS'),
                const SizedBox(height: 8),
                _alertCard([
                  _alertTile(
                    icon: Icons.error_outline,
                    color: Colors.red,
                    title: 'PMS Overdue',
                    sub: 'Notify when a vehicle is overdue for maintenance',
                    value: _pmsOverdue,
                    onChanged: (v) => setState(() => _pmsOverdue = v),
                  ),
                  _alertTile(
                    icon: Icons.today_outlined,
                    color: _red,
                    title: 'PMS Due Today',
                    sub: 'Notify when a vehicle\'s PMS is due today',
                    value: _pmsDueToday,
                    onChanged: (v) => setState(() => _pmsDueToday = v),
                  ),
                  _alertTile(
                    icon: Icons.calendar_today_outlined,
                    color: Colors.orange,
                    title: 'PMS Due This Week',
                    sub: 'Notify when PMS is due within 7 days',
                    value: _pmsDueThisWeek,
                    onChanged: (v) => setState(() => _pmsDueThisWeek = v),
                  ),
                  _alertTile(
                    icon: Icons.schedule_outlined,
                    color: Colors.amber.shade700,
                    title: 'PMS Due Soon',
                    sub: 'Notify when PMS is due within 14 days',
                    value: _pmsDueSoon,
                    onChanged: (v) => setState(() => _pmsDueSoon = v),
                    isLast: true,
                  ),
                ]),

                // ── Service Alerts (staff & admin) ─────────────────────
                if (isStaffOrAdmin) ...[
                  const SizedBox(height: 16),
                  _sectionLabel('SERVICE ALERTS'),
                  const SizedBox(height: 8),
                  _alertCard([
                    _alertTile(
                      icon: Icons.build_outlined,
                      color: Colors.green,
                      title: 'Service Updates',
                      sub: 'Notify on service status changes',
                      value: _serviceUpdate,
                      onChanged: (v) => setState(() => _serviceUpdate = v),
                    ),
                    _alertTile(
                      icon: Icons.assignment_outlined,
                      color: _blue,
                      title: 'New Assignment',
                      sub: 'Notify when a service is assigned to you',
                      value: _newAssignment,
                      onChanged: (v) => setState(() => _newAssignment = v),
                      isLast: true,
                    ),
                  ]),
                ],

                // ── Inventory Alerts (admin only) ──────────────────────
                if (isAdmin) ...[
                  const SizedBox(height: 16),
                  _sectionLabel('INVENTORY ALERTS'),
                  const SizedBox(height: 8),
                  _alertCard([
                    _alertTile(
                      icon: Icons.inventory_2_outlined,
                      color: Colors.orange,
                      title: 'Low Stock',
                      sub: 'Notify when stock falls below minimum level',
                      value: _lowStock,
                      onChanged: (v) => setState(() => _lowStock = v),
                      isLast: true,
                    ),
                  ]),
                ],

                // ── Booking Alerts ─────────────────────────────────────
                const SizedBox(height: 16),
                _sectionLabel('BOOKING ALERTS'),
                const SizedBox(height: 8),
                if (isCustomer)
                  _alertCard([
                    _alertTile(
                      icon: Icons.check_circle_outline,
                      color: Colors.green,
                      title: 'Booking Confirmed',
                      sub: 'Notify when your service booking is confirmed',
                      value: _bookingConfirmed,
                      onChanged: (v) => setState(() => _bookingConfirmed = v),
                    ),
                    _alertTile(
                      icon: Icons.notifications_outlined,
                      color: Colors.amber.shade700,
                      title: 'Booking Reminder',
                      sub: 'Remind you a day before your scheduled service',
                      value: _bookingReminder,
                      onChanged: (v) => setState(() => _bookingReminder = v),
                    ),
                    _alertTile(
                      icon: Icons.update_outlined,
                      color: _blue,
                      title: 'Booking Status Change',
                      sub: 'Notify on any update to your booking status',
                      value: _bookingStatusChange,
                      onChanged: (v) => setState(() => _bookingStatusChange = v),
                      isLast: true,
                    ),
                  ]),
                if (isStaffOrAdmin)
                  _alertCard([
                    _alertTile(
                      icon: Icons.event_available_outlined,
                      color: _blue,
                      title: 'New Booking Request',
                      sub: 'Notify when a new service booking is submitted',
                      value: _newBookingRequest,
                      onChanged: (v) => setState(() => _newBookingRequest = v),
                    ),
                    _alertTile(
                      icon: Icons.event_busy_outlined,
                      color: Colors.red,
                      title: 'Booking Cancellation',
                      sub: 'Notify when a customer cancels their booking',
                      value: _bookingCancellation,
                      onChanged: (v) => setState(() => _bookingCancellation = v),
                      isLast: true,
                    ),
                  ]),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _savePrefs,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Preferences',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
              ]),
            ),
    );
  }

  // ── Section label ────────────────────────────────────────────
  Widget _sectionLabel(String label) => Align(
    alignment: Alignment.centerLeft,
    child: Text(label, style: const TextStyle(
      fontSize: 11, fontWeight: FontWeight.w700,
      color: Color(0xFF718096), letterSpacing: 0.8)),
  );

  // ── Card wrapper ─────────────────────────────────────────────
  Widget _alertCard(List<Widget> tiles) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
    ),
    child: Column(children: tiles),
  );

  // ── Channel tile (larger icon area, descriptive sub) ─────────
  Widget _channelTile({
    required IconData icon,
    required Color color,
    required String title,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLast = false,
  }) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1a202c))),
            const SizedBox(height: 1),
            Text(sub, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ])),
          Switch.adaptive(value: value, onChanged: onChanged, activeColor: color),
        ]),
      ),
      if (!isLast) const Divider(height: 1, indent: 72),
    ]);
  }

  // ── Alert preference tile ────────────────────────────────────
  Widget _alertTile({
    required IconData icon,
    required Color color,
    required String title,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLast = false,
  }) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
            Text(sub, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ])),
          Switch.adaptive(value: value, onChanged: onChanged, activeColor: _red),
        ]),
      ),
      if (!isLast) const Divider(height: 1, indent: 66),
    ]);
  }
}
