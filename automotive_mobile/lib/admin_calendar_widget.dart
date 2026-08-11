import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// A floating calendar FAB + popup panel for PMS scheduling.
/// Use as an overlay widget via Stack in the parent page.
class PmsCalendarFloating extends StatefulWidget {
  const PmsCalendarFloating({super.key});

  @override
  State<PmsCalendarFloating> createState() => _PmsCalendarFloatingState();
}

class _PmsCalendarFloatingState extends State<PmsCalendarFloating>
    with SingleTickerProviderStateMixin {
  static const _red = Color(0xFFE8001C);
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  static const _dow = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  bool _panelOpen = false;
  late int _year;
  late int _month;
  String? _selectedDay;

  Map<String, List<Map<String, dynamic>>> _pmsEvents = {};
  bool _loading = true;
  int _urgentCount = 0;

  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _loadData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final db = FirebaseFirestore.instance;
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);

    final events = <String, List<Map<String, dynamic>>>{};
    int urgent = 0;

    // Load vehicles for PMS due dates
    final vehiclesSnap = await db.collection('vehicles').get();
    for (final doc in vehiclesSnap.docs) {
      final data = doc.data();
      final plate = data['plate'] as String? ?? '';
      final lastSvcDate = data['lastSvcDate'] as String? ?? '';
      final svcFreq = int.tryParse(data['svcFreq']?.toString() ?? '');

      if (lastSvcDate.isEmpty || svcFreq == null || plate.isEmpty) continue;
      final lastDate = DateTime.tryParse(lastSvcDate);
      if (lastDate == null) continue;

      final next = DateTime(lastDate.year, lastDate.month + svcFreq, lastDate.day);
      final nextMidnight = DateTime(next.year, next.month, next.day);
      final daysUntil = nextMidnight.difference(todayMidnight).inDays;

      final key = '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
      final urgency = daysUntil < 0 ? 'overdue' : daysUntil == 0 ? 'today' : daysUntil <= 7 ? 'week' : 'upcoming';
      urgent++; // all PMS dates (including upcoming) show the badge dot

      events.putIfAbsent(key, () => []);
      events[key]!.add({
        'plate': plate,
        'daysUntil': daysUntil,
        'urgency': urgency,
      });
    }

    // Load approved bookings
    final bookingsSnap = await db.collection('service_bookings')
        .where('status', isEqualTo: 'Approved')
        .get();
    for (final doc in bookingsSnap.docs) {
      final data = doc.data();
      final preferredDate = data['preferredDate'] as String? ?? '';
      if (preferredDate.isEmpty) continue;
      final plate = data['plate'] as String? ?? '—';
      final due = DateTime.tryParse(preferredDate);
      if (due == null) continue;
      final daysUntil = DateTime(due.year, due.month, due.day).difference(todayMidnight).inDays;

      events.putIfAbsent(preferredDate, () => []);
      events[preferredDate]!.add({
        'plate': '$plate (Booked)',
        'daysUntil': daysUntil,
        'urgency': 'booking',
      });
    }

    if (mounted) {
      // Auto-navigate to the nearest future PMS month
      String? nearestKey;
      for (final key in events.keys) {
        final evts = events[key]!;
        final hasFuturePms = evts.any((e) => e['urgency'] != 'booking' && (e['daysUntil'] as int) >= 0);
        if (!hasFuturePms) continue;
        if (nearestKey == null || key.compareTo(nearestKey) < 0) nearestKey = key;
      }
      int navYear = DateTime.now().year;
      int navMonth = DateTime.now().month;
      if (nearestKey != null) {
        final parts = nearestKey.split('-');
        navYear  = int.parse(parts[0]);
        navMonth = int.parse(parts[1]);
      }
      setState(() {
        _pmsEvents = events;
        _urgentCount = urgent;
        _loading = false;
        _year = navYear;
        _month = navMonth;
      });
    }
  }

  Color _urgencyColor(String urgency) {
    switch (urgency) {
      case 'overdue': return const Color(0xFFE8001C);
      case 'today':   return const Color(0xFF0033A0);
      case 'week': return const Color(0xFFed8936);
      case 'booking': return const Color(0xFF7c3aed);
      default: return const Color(0xFFEAB308);
    }
  }

  void _toggle() {
    setState(() {
      _panelOpen = !_panelOpen;
      if (_panelOpen) {
        _animCtrl.forward(from: 0);
      } else {
        _animCtrl.reverse();
      }
    });
  }

  void _navMonth(int dir) {
    setState(() {
      _month += dir;
      if (_month > 12) { _month = 1; _year++; }
      if (_month < 1) { _month = 12; _year--; }
      _selectedDay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Dismiss on tap outside
      if (_panelOpen)
        Positioned.fill(
          child: GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.black.withOpacity(0.15)),
          ),
        ),

      // Floating panel
      if (_panelOpen)
        Positioned(
          bottom: 80,
          right: 16,
          child: ScaleTransition(
            scale: _scaleAnim,
            alignment: Alignment.bottomRight,
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(18),
              shadowColor: Colors.black.withOpacity(0.2),
              child: Container(
                width: 310,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFe2e8f0)),
                ),
                child: _loading
                    ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
                    : _buildPanel(),
              ),
            ),
          ),
        ),

      // FAB
      Positioned(
        bottom: 16,
        right: 16,
        child: GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFFE8001C), Color(0xFFc0001a)]),
              boxShadow: [BoxShadow(color: _red.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4))],
            ),
            child: Stack(alignment: Alignment.center, children: [
              const Icon(Icons.calendar_month_outlined, color: Colors.white, size: 22),
              if (_urgentCount > 0 && !_panelOpen)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFFfbbf24),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _buildPanel() {
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFE8001C), Color(0xFFc0001a)]),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.calendar_month_outlined, color: Colors.white70, size: 14),
              const SizedBox(width: 6),
              const Text('PMS Schedule', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70, letterSpacing: 0.5)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$_year', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(
                onTap: () => _navMonth(-1),
                child: Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.chevron_left, size: 18, color: Colors.white),
                ),
              ),
              Text(_months[_month - 1], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              GestureDetector(
                onTap: () => _navMonth(1),
                child: Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.chevron_right, size: 18, color: Colors.white),
                ),
              ),
            ]),
          ]),
        ),

        // Calendar grid
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: _buildCalendarGrid(),
        ),

        // Day detail
        if (_selectedDay != null) _buildDayDetail(),

        // Legend
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: Wrap(spacing: 12, runSpacing: 4, children: [
            _legendItem(const Color(0xFFE8001C), 'Overdue'),
            _legendItem(const Color(0xFFed8936), 'This Week'),
            _legendItem(const Color(0xFFEAB308), 'Upcoming'),
            _legendItem(const Color(0xFF0033A0), 'Today'),
            _legendItem(const Color(0xFF7c3aed), 'Booked'),
          ]),
        ),
      ]),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF4a5568))),
    ]);
  }

  Widget _buildCalendarGrid() {
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final firstDayOfMonth = DateTime(_year, _month, 1);
    final firstWeekday = firstDayOfMonth.weekday % 7;
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final prevMonthDays = DateTime(_year, _month, 0).day;

    final cells = <Widget>[];

    // DOW headers
    for (final d in _dow) {
      cells.add(Center(child: Text(d,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFa0aec0)))));
    }

    // Previous month
    for (int i = firstWeekday - 1; i >= 0; i--) {
      cells.add(Container(
        decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(5)),
        child: Center(child: Text('${prevMonthDays - i}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade300))),
      ));
    }

    // Current month
    for (int d = 1; d <= daysInMonth; d++) {
      final key = '$_year-${_month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      final events = _pmsEvents[key] ?? [];
      final isToday = key == todayKey;
      final isSelected = key == _selectedDay;

      cells.add(GestureDetector(
        onTap: events.isNotEmpty ? () {
          setState(() { _selectedDay = _selectedDay == key ? null : key; });
        } : null,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFebf8ff)
                : isToday
                    ? const Color(0xFFEEF2FF)
                    : const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? const Color(0xFF003087) : isToday ? const Color(0xFF0033A0) : Colors.transparent,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(2),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$d', style: TextStyle(
              fontSize: 11,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              color: isToday ? const Color(0xFF0033A0) : const Color(0xFF4a5568),
            )),
            if (events.isNotEmpty) ...[
              const SizedBox(height: 1),
              Wrap(spacing: 2, runSpacing: 1, alignment: WrapAlignment.center, children:
                events.take(3).map((e) => Container(
                  width: 5, height: 5,
                  decoration: BoxDecoration(
                    color: _urgencyColor(e['urgency'] as String),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                )).toList(),
              ),
            ],
          ]),
        ),
      ));
    }

    // Trailing
    final totalCells = firstWeekday + daysInMonth;
    final trailing = totalCells % 7 == 0 ? 0 : 7 - (totalCells % 7);
    for (int d = 1; d <= trailing; d++) {
      cells.add(Container(
        decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(5)),
        child: Center(child: Text('$d', style: TextStyle(fontSize: 11, color: Colors.grey.shade300))),
      ));
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 3,
      crossAxisSpacing: 3,
      childAspectRatio: 1.1,
      children: cells,
    );
  }

  Widget _buildDayDetail() {
    final events = _pmsEvents[_selectedDay] ?? [];
    if (events.isEmpty) return const SizedBox.shrink();

    final parts = _selectedDay!.split('-');
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    final y = int.parse(parts[0]);
    final title = '${_months[m - 1]} $d, $y';

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF718096), letterSpacing: 0.3)),
        const SizedBox(height: 6),
        ...events.map((e) {
          final color = _urgencyColor(e['urgency'] as String);
          final daysUntil = e['daysUntil'] as int;
          final String label;
          if (e['urgency'] == 'booking') {
            label = daysUntil < 0 ? 'Past' : daysUntil == 0 ? 'Today' : 'In $daysUntil day${daysUntil != 1 ? 's' : ''}';
          } else {
            label = daysUntil < 0
                ? '${(-daysUntil)} day${(-daysUntil) != 1 ? 's' : ''} overdue'
                : daysUntil == 0
                    ? 'Due Today'
                    : 'Due in $daysUntil day${daysUntil != 1 ? 's' : ''}';
          }
          return Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFe2e8f0)),
            ),
            child: Row(children: [
              Container(width: 8, height: 8,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Expanded(child: Text(e['plate'] as String,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1a202c)))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}
