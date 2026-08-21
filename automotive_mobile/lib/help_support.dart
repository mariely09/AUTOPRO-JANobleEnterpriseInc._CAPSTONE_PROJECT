import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum HelpSupportRole { customer, staff, admin }

class HelpSupportScreen extends StatefulWidget {
  final HelpSupportRole role;
  const HelpSupportScreen({super.key, this.role = HelpSupportRole.customer});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  static const _red = Color(0xFFE8001C);
  static const _blue = Color(0xFF003087);

  int? _expandedIndex;

  List<Map<String, String>> get _faqs {
    switch (widget.role) {
      case HelpSupportRole.admin:
        return const [
          {
            'q': 'What sections are available in the admin panel?',
            'a':
                'The admin panel has four main sections: Inventory Management (Item Master, Stock Inventory, Receiving Items, Inventory Transactions), Vehicle Maintenance (Vehicle List, Vehicle Maintenance, Service Bookings, Issuances), Decision Support System (Stock Replenishment, PMS Scheduling), and Administration (User Management, Domain Management, Archive).',
          },
          {
            'q': 'How do I manage the Item Master?',
            'a':
                'Go to Item Master under Inventory Management. You can add new items (materials or services), edit existing ones, set commodity group, UOM, cost, and supplier code, and archive items that are no longer in use.',
          },
          {
            'q': 'How does the Receiving Items workflow work?',
            'a':
                'Deliveries go through a 3-step process: (1) Pending — a delivery is created and items are received with actual quantities and condition noted. (2) Awaiting Double Check — admin reviews and verifies the received quantities. (3) Approved — stock is updated automatically. Admin can also approve or reject staff delivery requests marked "For Admin Review".',
          },
          {
            'q': 'How do I approve or reject a service booking?',
            'a':
                'Go to Service Bookings under Vehicle Maintenance. You will see all incoming customer booking requests. You can Approve, Reschedule, or Dismiss each request. Approved bookings become available to staff for scheduling.',
          },
          {
            'q': 'What is the Decision Support System (DSS)?',
            'a':
                'The DSS has two tools: Stock Replenishment shows items that are low or out of stock with reorder recommendations, and PMS Scheduling suggests vehicles that are due or overdue for preventive maintenance based on their service schedule.',
          },
          {
            'q': 'How do I manage users?',
            'a':
                'Go to User Management under Administration. You can add new staff or customer accounts (credentials are auto-generated and emailed), edit user details and roles, and activate or deactivate accounts.',
          },
          {
            'q': 'How do I change my password?',
            'a':
                'Go to your Profile page and tap Change Password. Enter your current password, then your new password (minimum 6 characters), and confirm it to save.',
          },
        ];
      case HelpSupportRole.staff:
        return const [
          {
            'q': 'What tabs are available in the app?',
            'a':
                'The app has four tabs: Dashboard (overview), Inventory (stock levels and receiving), Vehicle (maintenance records), and Profile. There is also a red scanner button at the center of the bottom bar for scanning barcodes and QR codes.',
          },
          {
            'q': 'How do I view and filter stock inventory?',
            'a':
                'Tap the Inventory tab. You will see stock cards with status chips: Total Items, Out of Stock, Low Stock, and In Stock. Tap a chip to filter. You can also sort by item number, name, or stock level, and filter by commodity group using the menu at the top right.',
          },
          {
            'q': 'How do I submit a delivery request?',
            'a':
                'In the Inventory tab, tap the Receiving sub-tab. Tap the red FAB button and select "New Delivery Request". Choose items from the replenishment list (items that are low or out of stock), set the order quantities, and submit. Your request will be sent to admin for review.',
          },
          {
            'q': 'How do I receive an item from a delivery?',
            'a':
                'In the Receiving tab, find a Pending item and tap it to open the details. Tap "Receive Item", enter the actual quantity received, select the condition (OK, Defective, or Shortage), add any remarks, and submit. The item will move to "Awaiting Double Check" for admin verification.',
          },
          {
            'q': 'How do I use the barcode scanner?',
            'a':
                'Tap the red scanner button at the center of the bottom navigation bar. Point the camera at a barcode or QR code to find the matching item. If a pending delivery contains that item, you will be taken directly to the receive screen for it.',
          },
          {
            'q': 'How do I add a vehicle maintenance record?',
            'a':
                'Go to the Vehicle tab and tap the red + button. Select the vehicle by plate number, assign a mechanic, set the date and odometer reading. Then add the services rendered (from the service catalog) and the materials used. Save to create the record.',
          },
          {
            'q': 'What happens when I mark a maintenance record as completed?',
            'a':
                'Marking a record as Completed automatically deducts the used materials from stock inventory, creates issuance records for each material, and logs stock-out transactions. Make sure all services and materials are entered correctly before completing.',
          },
          {
            'q': 'How do I handle service bookings?',
            'a':
                'Go to the Vehicle tab and open Service Bookings. You can see all admin-approved bookings. On the scheduled date, the "Start Service" button becomes active — tap it to open a pre-filled maintenance form for that booking. You can also reschedule or cancel a booking from this screen.',
          },
          {
            'q': 'How do I change my password?',
            'a':
                'Go to your Profile page and tap Change Password. Enter your current password, then your new password (minimum 6 characters), and confirm it to save.',
          },
          {
            'q': 'I forgot my password. What should I do?',
            'a':
                'On the login screen, tap "Forgot Password". Enter your email address to receive a 6-digit OTP. Enter the OTP to verify, then check your email for the password reset link.',
          },
        ];
      case HelpSupportRole.customer:
        return const [
          {
            'q': 'What tabs are available in the app?',
            'a':
                'The app has five tabs: Home (My Vehicles), My Bookings, AI Assistant (the center button), PMS History, and Profile.',
          },
          {
            'q': 'How do I view my vehicles?',
            'a':
                'Tap the Home tab to see all your registered vehicles. Each card shows the plate number, vehicle description, current odometer, last service date, and current status (Active, PMS Due Soon, or Overdue).',
          },
          {
            'q': 'Why is my vehicle showing "Overdue" or "PMS Due Soon"?',
            'a':
                'This is calculated automatically based on the last service date and service frequency on record. "PMS Due Soon" means the next scheduled maintenance is approaching, and "Overdue" means it has already passed. Contact the service center to schedule a maintenance.',
          },
          {
            'q': 'How do I book a service?',
            'a':
                'Tap the Bookings tab and then tap the + button. Select your vehicle, choose the services you need, and pick your preferred date and time. Your request will be sent to the admin for approval. You will receive a notification once it is approved, rescheduled, or cancelled.',
          },
          {
            'q': 'How do I view my service history?',
            'a':
                'Tap the PMS History tab to see a list of your vehicles. Tap any vehicle to view its full maintenance history, including the service date, mechanic, services rendered, materials used, and total cost.',
          },
          {
            'q': 'What is the AI Assistant?',
            'a':
                'The AI Assistant is the center button at the bottom of the screen. Tap it to open the chat. You can ask it questions about your vehicles — such as which ones are overdue, when the next service is due, or get a summary of your maintenance history. Just type your question in natural language.',
          },
          {
            'q': 'How do I change my profile photo?',
            'a':
                'Go to your Profile page and tap your avatar photo at the top. This will open your gallery so you can select a new image.',
          },
          {
            'q': 'I forgot my password. What should I do?',
            'a':
                'On the login screen, tap "Forgot Password". Enter your email to receive a 6-digit OTP. Enter the OTP to verify, then check your email for the password reset link.',
          },
        ];
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Help & Support',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1a202c), Color(0xFF2d3748), _red],
                  stops: [0.0, 0.6, 1.0],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.support_agent_outlined,
                    color: Colors.white,
                    size: 32,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'How can we help?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Browse FAQs or reach out to our support team.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // FAQs
            _sectionLabel('FREQUENTLY ASKED QUESTIONS'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                children: List.generate(_faqs.length, (i) {
                  final isLast = i == _faqs.length - 1;
                  final isOpen = _expandedIndex == i;
                  return Column(
                    children: [
                      InkWell(
                        onTap: () =>
                            setState(() => _expandedIndex = isOpen ? null : i),
                        borderRadius: isLast && !isOpen
                            ? const BorderRadius.vertical(
                                bottom: Radius.circular(14),
                              )
                            : BorderRadius.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F3F5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.help_outline,
                                  size: 16,
                                  color: Color(0xFF1a202c),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _faqs[i]['q']!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isOpen
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: const Color(0xFF1a202c),
                                  ),
                                ),
                              ),
                              Icon(
                                isOpen ? Icons.expand_less : Icons.expand_more,
                                size: 20,
                                color: const Color(0xFF718096),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isOpen)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(60, 0, 16, 14),
                          child: Text(
                            _faqs[i]['a']!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4a5568),
                              height: 1.5,
                            ),
                          ),
                        ),
                      if (!isLast) const Divider(height: 1, indent: 60),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 20),

            // Contact
            _sectionLabel('CONTACT US'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                children: [
                  _contactTile(
                    icon: Icons.phone_outlined,
                    color: const Color(0xFF1a202c),
                    label: 'Call Us',
                    value: '+63 912 345 6789',
                    onTap: () => _launch('tel:+639123456789'),
                  ),
                  const Divider(height: 1, indent: 66),
                  _contactTile(
                    icon: Icons.email_outlined,
                    color: const Color(0xFF1a202c),
                    label: 'Email Support',
                    value: 'janobleenterprisesinc@gmail.com',
                    onTap: () =>
                        _launch('mailto:janobleenterprisesinc@gmail.com'),
                  ),
                  const Divider(height: 1, indent: 66),
                  _contactTile(
                    icon: Icons.location_on_outlined,
                    color: const Color(0xFF1a202c),
                    label: 'Visit Us',
                    value:
                        '102 National Highway, Brgy. Landayan, San Pedro, Laguna',
                    onTap: () => _launch(
                      'https://www.google.com/maps/search/?api=1&query=102+National+Highway+Bgy+Landayan+4023+San+Pedro+Laguna+Philippines',
                    ),
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Hours
            _sectionLabel('BUSINESS HOURS'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                children: [_hoursRow('Monday – Sunday', '8:00 AM – 5:00 PM')],
              ),
            ),
            const SizedBox(height: 24),

            const Center(
              child: Text(
                'v1.0.0 • JA Noble Enterprise',
                style: TextStyle(fontSize: 11, color: Color(0xFFa0aec0)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
    label,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Color(0xFF718096),
      letterSpacing: 0.8,
    ),
  );

  Widget _contactTile({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required VoidCallback? onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: isLast
          ? const BorderRadius.vertical(bottom: Radius.circular(14))
          : BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF718096),
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1a202c),
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xFF718096),
              ),
          ],
        ),
      ),
    );
  }

  Widget _hoursRow(String day, String hours) {
    final isClosed = hours == 'Closed';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          day,
          style: const TextStyle(fontSize: 13, color: Color(0xFF4a5568)),
        ),
        Text(
          hours,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isClosed ? Colors.red : const Color(0xFF1a202c),
          ),
        ),
      ],
    );
  }
}
