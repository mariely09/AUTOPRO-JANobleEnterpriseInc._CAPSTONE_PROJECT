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
  String _sortOrder = 'num_asc';     // item master sort
  String _stockSortOrder = 'num-asc'; // stock inventory sort
  String _stockGroupFilter = '';      // stock group filter
  String _itemMasterGroupFilter = ''; // item master group filter

  // Key to access AdminReceivingBodyState for auto-opening the receive modal
  final _receivingKey = GlobalKey<AdminReceivingBodyState>();
  final _stockBodyKey = GlobalKey<AdminInventoryStockBodyState>();
  final _itemMasterKey = GlobalKey<AdminInventoryItemMasterBodyState>();

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
          // Sort+Filter popup for Stock tab
          if (_tab == 0 && !_searching)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (val) {
                if (val.startsWith('sort:')) {
                  setState(() => _stockSortOrder = val.substring(5));
                } else if (val.startsWith('group:')) {
                  setState(() => _stockGroupFilter = val.substring(6));
                }
              },
              itemBuilder: (_) {
                final groupList = _stockBodyKey.currentState?.groups.isNotEmpty == true
                    ? _stockBodyKey.currentState!.groups
                    : ['Lubricants', 'Spare Parts', 'Filter', 'AutoService'];
                return [
                  const PopupMenuItem(enabled: false, child: Text('Sort By', style: TextStyle(fontSize: 11, color: Color(0xFF718096), fontWeight: FontWeight.w700))),
                  _stockPopItem('sort:num-asc',    'Item No. (Ascending)',  Icons.arrow_upward,    _stockSortOrder == 'num-asc',    _red),
                  _stockPopItem('sort:num-desc',   'Item No. (Descending)', Icons.arrow_downward,  _stockSortOrder == 'num-desc',   _red),
                  _stockPopItem('sort:name-asc',   'Name A → Z',            Icons.sort_by_alpha,   _stockSortOrder == 'name-asc',   _red),
                  _stockPopItem('sort:name-desc',  'Name Z → A',            Icons.sort_by_alpha,   _stockSortOrder == 'name-desc',  _red),
                  _stockPopItem('sort:stock-desc', 'Stock ↑ Highest',       Icons.trending_up,     _stockSortOrder == 'stock-desc', _red),
                  _stockPopItem('sort:stock-asc',  'Stock ↓ Lowest',        Icons.trending_down,   _stockSortOrder == 'stock-asc',  _red),
                  const PopupMenuDivider(),
                  const PopupMenuItem(enabled: false, child: Text('Filter by Group', style: TextStyle(fontSize: 11, color: Color(0xFF718096), fontWeight: FontWeight.w700))),
                  _stockPopItem('group:',  'All Groups', Icons.select_all, _stockGroupFilter.isEmpty, const Color(0xFF003087)),
                  ...groupList.map((g) => _stockPopItem('group:$g', g, Icons.circle_outlined, _stockGroupFilter == g, const Color(0xFF003087))),
                ];
              },
            ),
          if (_tab == 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (val) {
                if (val.startsWith('sort:')) {
                  setState(() => _sortOrder = val.substring(5));
                } else if (val.startsWith('group:')) {
                  setState(() => _itemMasterGroupFilter = val.substring(6));
                }
              },
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              itemBuilder: (_) {
                final groupList = _itemMasterKey.currentState?.groups.isNotEmpty == true
                    ? _itemMasterKey.currentState!.groups
                    : ['Lubricants', 'Spare Parts', 'Filter', 'AutoService'];
                return [
                  const PopupMenuItem(enabled: false, child: Text('Sort By', style: TextStyle(fontSize: 11, color: Color(0xFF718096), fontWeight: FontWeight.w700))),
                  _sortItem('num_asc',   'Item No. (Ascending)',  Icons.arrow_upward),
                  _sortItem('num_desc',  'Item No. (Descending)', Icons.arrow_downward),
                  _sortItem('name_asc',  'Name A → Z',            Icons.sort_by_alpha),
                  _sortItem('name_desc', 'Name Z → A',            Icons.sort_by_alpha),
                  _sortItem('cost_desc', 'Cost ↑ Highest',        Icons.trending_up),
                  _sortItem('cost_asc',  'Cost ↓ Lowest',         Icons.trending_down),
                  const PopupMenuDivider(),
                  const PopupMenuItem(enabled: false, child: Text('Filter by Group', style: TextStyle(fontSize: 11, color: Color(0xFF718096), fontWeight: FontWeight.w700))),
                  _stockPopItem('group:',  'All Groups', Icons.select_all,     _itemMasterGroupFilter.isEmpty, const Color(0xFF003087)),
                  ...groupList.map((g) => _stockPopItem('group:$g', g, Icons.circle_outlined, _itemMasterGroupFilter == g, const Color(0xFF003087))),
                ];
              },
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
                    behavior: HitTestBehavior.opaque,
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final sq = _searching ? _searchCtrl.text.toLowerCase() : '';
    return Stack(children: [
      Offstage(
        offstage: _tab != 0,
        child: AdminInventoryStockBody(
          key: _stockBodyKey,
          searchQuery: _tab == 0 ? sq : '',
          sortOrder: _stockSortOrder,
          groupFilter: _stockGroupFilter),
      ),
      Offstage(
        offstage: _tab != 1,
        child: AdminInventoryItemMasterBody(
          key: _itemMasterKey,
          searchQuery: _tab == 1 ? sq : '',
          sortOrder: _sortOrder,
          groupFilter: _itemMasterGroupFilter,
          onStockSaved: () {
            setState(() { _tab = 0; _searching = false; _searchCtrl.clear(); });
          }),
      ),
      Offstage(
        offstage: _tab != 2,
        child: AdminReceivingBody(
          key: _receivingKey,
          searchQuery: _tab == 2 ? sq : ''),
      ),
      Offstage(
        offstage: _tab != 3,
        child: AdminTransactionsBody(
          searchQuery: _tab == 3 ? sq : ''),
      ),
    ]);
  }

  PopupMenuItem<String> _stockPopItem(String value, String label, IconData icon, bool active, Color color) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, size: 16, color: active ? color : const Color(0xFF718096)),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 13, color: active ? color : const Color(0xFF1a202c), fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
        if (active) ...[const Spacer(), Icon(Icons.check, size: 14, color: color)],
      ]),
    );
  }

  PopupMenuItem<String> _stockSortItem(String value, String label, IconData icon) {
    final active = _stockSortOrder == value;
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, size: 16, color: active ? _red : const Color(0xFF718096)),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(
          fontSize: 13,
          color: active ? _red : const Color(0xFF1a202c),
          fontWeight: active ? FontWeight.w700 : FontWeight.normal,
        )),
        if (active) ...[
          const Spacer(),
          const Icon(Icons.check, size: 14, color: Color(0xFFE8001C)),
        ],
      ]),
    );
  }

  PopupMenuItem<String> _sortItem(String value, String label, IconData icon) {
    final active = _sortOrder == value;
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, size: 16, color: active ? _red : const Color(0xFF718096)),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(
          fontSize: 13,
          color: active ? _red : const Color(0xFF1a202c),
          fontWeight: active ? FontWeight.w700 : FontWeight.normal,
        )),
        if (active) ...[
          const Spacer(),
          const Icon(Icons.check, size: 14, color: Color(0xFFE8001C)),
        ],
      ]),
    );
  }
}
