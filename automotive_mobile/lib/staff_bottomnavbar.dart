import 'package:flutter/material.dart';
import 'barcode_scanner_screen.dart';

class StaffBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onScanPressed;
  static const Color _red = Color(0xFFE8001C);

  const StaffBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.onScanPressed,
  });

  static const List<_NavItem> navItems = [
    _NavItem(icon: Icons.dashboard_outlined, label: 'Dashboard'),
    _NavItem(icon: Icons.inventory_2_outlined, label: 'Inventory'),
    _NavItem(icon: Icons.directions_car_outlined, label: 'Assets'),
    _NavItem(icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x18000000), blurRadius: 12, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 4 slots: 2 left + center placeholder + 2 right
              Row(children: [
                _navBtn(0), // Dashboard
                _navBtn(1), // Inventory
                const Expanded(child: SizedBox()), // center placeholder for scan button
                _navBtn(2), // Vehicle
                _navBtn(3), // Profile
              ]),
              // Center scan button
              Positioned(
                top: -20,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: onScanPressed,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _red.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ],
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navBtn(int i) {
    final active = currentIndex == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => onIndexChanged(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              navItems[i].icon,
              color: active ? _red : const Color(0xFF718096),
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              navItems[i].label,
              style: TextStyle(
                fontSize: 10,
                color: active ? _red : const Color(0xFF718096),
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem({required this.icon, required this.label});
}
