import 'package:flutter/material.dart';

/// Bottom navigation bar for the Customer Dashboard.
/// Indices:
///   0 → Home (My Vehicles)
///   1 → My Bookings
///   2 → PMS History
///   3 → Profile
class CustomerBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _red  = Color(0xFFE8001C);
  static const _grey = Color(0xFF718096);

  const CustomerBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
            color: Color(0x18000000), blurRadius: 12, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(children: [
            _navBtn(0),
            _navBtn(1),
            _navBtn(2),
            _navBtn(3),
          ]),
        ),
      ),
    );
  }

  Widget _navBtn(int i) {
    final active = currentIndex == i;
    const labels = ['Home', 'Bookings', 'PMS History', 'Profile'];
    const icons  = [
      Icons.home_outlined,
      Icons.list_alt_outlined,
      Icons.history,
      Icons.person_outline,
    ];
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(i),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icons[i], size: 22, color: active ? _red : _grey),
            const SizedBox(height: 2),
            Text(labels[i], style: TextStyle(
              fontSize: 10,
              color: active ? _red : _grey,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }
}
