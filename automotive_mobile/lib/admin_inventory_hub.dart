import 'package:flutter/material.dart';
import 'admin_inventory_itemaster.dart';
import 'admin_inventory_stock.dart';
import 'admin_receiving.dart';
import 'admin_transactions.dart';

/// Full-screen Inventory hub — AppBar with 4 sub-tabs, no bottom nav.
/// Mirrors the same pattern as AdminVehiclesList.
class AdminInventoryHub extends StatefulWidget {
  /// Which tab to open initially (0=Stock, 1=Item Master, 2=Receiving, 3=Transactions)
  final int initialTab;
  /// If set, auto-opens the receive modal for this delivery on the Receiving tab.
  final Map<String, dynamic>? deliveryToReceive;
  const AdminInventoryHub({super.key, this.initialTab = 0, this.deliveryToReceive});

  @override
  State<AdminInventoryHub> createState() => _AdminInventoryHubState();
}

class _AdminInventoryHubState extends State<AdminInventoryHub> {
  static const _red = Color(0xFFE8001C);

  // 0=Stock, 1=Item Master, 2=Receiving, 3=Transactions
  late int _tab;
  bool _searching = false;
  final _searchCtrl = TextEditingController();

  // Key to access AdminReceivingBodyState for auto-opening the receive modal
  final _receivingKey = GlobalKey<AdminReceivingBodyState>();

  static const _tabs      = ['Stock', 'Item Master', 'Receiving', 'Transactions'];
  static const _tabTitles = ['Stock Inventory', 'Item Master', 'Receiving Items', 'Transactions'];

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 3);
    // Auto-open the receive modal after the first frame if a delivery was passed
    if (widget.deliveryToReceive != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _receivingKey.currentState?.openReceiveModal(widget.deliveryToReceive!);
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
              )
            : Text(
                _tabTitles[_tab],
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
        actions: [
          IconButton(
            icon: Icon(
                _searching ? Icons.close : Icons.search,
                color: Colors.white),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _searchCtrl.clear();
            }),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: Colors.white,
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final active = _tab == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _tab = i;
                      _searching = false;
                      _searchCtrl.clear();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: active ? _red : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        _tabs[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                          color: active ? _red : const Color(0xFF718096),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          AdminInventoryStockBody(
            searchQuery: _tab == 0 && _searching ? _searchCtrl.text.toLowerCase() : ''),
          AdminInventoryItemMasterBody(
            searchQuery: _tab == 1 && _searching ? _searchCtrl.text.toLowerCase() : ''),
          AdminReceivingBody(
            key: _receivingKey,
            searchQuery: _tab == 2 && _searching ? _searchCtrl.text.toLowerCase() : ''),
          AdminTransactionsBody(
            searchQuery: _tab == 3 && _searching ? _searchCtrl.text.toLowerCase() : ''),
        ],
      ),
    );
  }
}
