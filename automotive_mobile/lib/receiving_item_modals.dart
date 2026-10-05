import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'sync_indicator.dart';

// Shared receiving modals: AddItemFormModal, LineViewModal, EditLineModal

const _rcvCol = 'receivings';
const _kRed   = Color(0xFFE8001C);
const _kGreen = Color(0xFF38a169);
const _kAmber = Color(0xFFd69e2e);
const _kGrey  = Color(0xFF718096);

Color _lineColor(String s) {
  switch (s) {
    case 'COMP':      return _kGreen;
    case 'INCOMP':    return _kAmber;
    case 'MISSING':   return _kRed;
    case 'DEFECTIVE': return _kRed;
    default:          return _kGrey;
  }
}

const _lineLabels = {
  'DRAFT': 'Draft', 'COMP': 'Complete', 'INCOMP': 'Incomplete',
  'MISSING': 'Missing', 'DEFECTIVE': 'Defective',
};

// ── Floating-label field ───────────────────────────────────────────────────
class RcvFloatField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool required;
  final TextInputType keyboardType;
  final ValueChanged<String>? onChanged;
  const RcvFloatField({
    super.key,
    required this.controller,
    required this.label,
    this.required = false,
    this.keyboardType = TextInputType.text,
    this.onChanged,
  });
  @override
  State<RcvFloatField> createState() => _RcvFloatFieldState();
}

class _RcvFloatFieldState extends State<RcvFloatField> {
  late FocusNode _f;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _f = FocusNode()..addListener(() {
      if (mounted) setState(() => _focused = _f.hasFocus);
    });
  }

  @override
  void dispose() { _f.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final floated = _focused || widget.controller.text.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _focused ? _kRed : const Color(0xFFc5cdd9), width: 1.5),
        boxShadow: _focused ? [BoxShadow(color: _kRed.withValues(alpha: 0.1), blurRadius: 0, spreadRadius: 3)] : [],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextField(
              controller: widget.controller,
              focusNode: _f,
              keyboardType: widget.keyboardType,
              style: const TextStyle(fontSize: 15, color: Color(0xFF1a202c)),
              onChanged: widget.onChanged,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.fromLTRB(12, 18, 12, 6),
                border: InputBorder.none,
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 160),
            left: 12, top: floated ? 4 : 14,
            child: IgnorePointer(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 160),
                style: TextStyle(
                  fontSize: floated ? 10 : 14,
                  color: _focused ? _kRed : const Color(0xFFa0aec0),
                  fontWeight: FontWeight.w500,
                ),
                child: Text(widget.label + (widget.required ? ' *' : '')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Read-only field ────────────────────────────────────────────────────────
Widget rcvRoField(String label, String value) => Container(
  width: double.infinity,
  padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
  decoration: BoxDecoration(
    color: Colors.white,
    border: Border.all(color: const Color(0xFFc5cdd9), width: 1.5),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(top: -14, left: 0,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF718096), fontWeight: FontWeight.w500)),
        ),
      ),
      Text(value.isEmpty ? '—' : value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
    ],
  ),
);

// ── Mini stat card ─────────────────────────────────────────────────────────
Widget rcvMiniCard(String label, String value, Color color) => Expanded(
  child: Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFFa0aec0), fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
      ],
    ),
  ),
);

// ── Red modal header ───────────────────────────────────────────────────────
Widget rcvRedHeader({required String title, required String subtitle, required VoidCallback onClose}) =>
  Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFFE8001C), Color(0xFFC41E3A)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ],
          ),
        ),
        GestureDetector(
          onTap: onClose,
          child: Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
            child: const Icon(Icons.close, color: Colors.white, size: 18),
          ),
        ),
      ],
    ),
  );

// ═══════════════════════════════════════════════════════════════════════════
// ADD ITEM FORM MODAL
// ═══════════════════════════════════════════════════════════════════════════

void showAddItemFormModal(BuildContext context, {
  required Map<String, dynamic> rcvData,
  VoidCallback? onAdded,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AddItemFormSheet(rcvData: rcvData, onAdded: onAdded),
  );
}

class _AddItemFormSheet extends StatefulWidget {
  final Map<String, dynamic> rcvData;
  final VoidCallback? onAdded;
  const _AddItemFormSheet({required this.rcvData, this.onAdded});
  @override
  State<_AddItemFormSheet> createState() => _AddItemFormSheetState();
}

class _AddItemFormSheetState extends State<_AddItemFormSheet> {
  final _numCtrl  = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _uomCtrl  = TextEditingController();
  final _scCtrl   = TextEditingController();
  final _qtyCtrl  = TextEditingController();
  final _oemCtrl  = TextEditingController();
  final _posCtrl  = TextEditingController();

  List<Map<String, dynamic>> _numSugs  = [];
  List<Map<String, dynamic>> _nameSugs = [];
  bool _suppressSearch = false;
  Timer? _debounce;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_numCtrl,_nameCtrl,_uomCtrl,_scCtrl,_qtyCtrl,_oemCtrl,_posCtrl]) c.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String field, String val) {
    if (_suppressSearch) return;
    _debounce?.cancel();
    if (val.trim().isEmpty) {
      setState(() { if (field == 'num') _numSugs = []; else _nameSugs = []; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final q = val.trim();
      final startKey = q[0].toUpperCase() + q.substring(1);
      final orderField = field == 'num' ? 'num' : 'name';
      try {
        final snap = await FirebaseFirestore.instance
            .collection('stock_inventory')
            .orderBy(orderField)
            .startAt([startKey]).endAt(['$startKey\uf8ff'])
            .limit(8).get();
        if (!mounted) return;
        setState(() {
          final r = snap.docs.map((d) => {...d.data(), '_id': d.id}).toList();
          if (field == 'num') _numSugs = r; else _nameSugs = r;
        });
      } catch (_) {}
    });
  }

  Future<void> _select(Map<String, dynamic> item) async {
    _suppressSearch = true;
    setState(() { _numSugs = []; _nameSugs = []; });
    _numCtrl.text  = item['num']          as String? ?? '';
    _nameCtrl.text = item['name']         as String? ?? '';
    _uomCtrl.text  = item['uom']          as String? ?? '';
    _scCtrl.text   = item['supplierCode'] as String? ?? '';
    _oemCtrl.text  = item['oem']          as String? ?? '';
    setState(() {});

    final num = item['num'] as String? ?? '';
    if (num.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('item_master').where('num', isEqualTo: num).limit(1).get();
        if (!mounted) return;
        if (snap.docs.isNotEmpty) {
          final m = snap.docs.first.data();
          _numCtrl.text  = m['num']  as String? ?? m['itemNum']  as String? ?? _numCtrl.text;
          _nameCtrl.text = m['name'] as String? ?? m['itemName'] as String? ?? _nameCtrl.text;
          if (_uomCtrl.text.isEmpty) _uomCtrl.text = m['uom'] as String? ?? '';
          if (_scCtrl.text.isEmpty)  _scCtrl.text  = m['supplierCode'] as String? ?? '';
          if (_oemCtrl.text.isEmpty) _oemCtrl.text =
              m['oem'] as String? ?? m['oem_num'] as String? ?? m['oemNum'] as String? ?? '';
          setState(() {});
        }
      } catch (_) {}
    }
    _suppressSearch = false;
    FocusScope.of(context).unfocus();
  }

  Future<void> _save() async {
    final itemNum  = _numCtrl.text.trim();
    final itemName = _nameCtrl.text.trim();
    final poQty    = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (itemNum.isEmpty)  { _err('Item No. is required.'); return; }
    if (itemName.isEmpty) { _err('Item Name is required.'); return; }
    if (poQty < 1)        { _err('Order Qty must be at least 1.'); return; }

    setState(() => _saving = true);
    final docId = widget.rcvData['id'] as String;
    final lines = List<Map<String, dynamic>>.from(
        (widget.rcvData['receivingLines'] as List? ?? []).map((l) => Map<String, dynamic>.from(l as Map)));
    lines.add({
      'itemNum': itemNum, 'itemName': itemName,
      'uom': _uomCtrl.text.trim(), 'supplierCode': _scCtrl.text.trim(),
      'oem': _oemCtrl.text.trim(), 'posId': _posCtrl.text.trim(),
      'poQty': poQty, 'receivedQty': 0, 'lineStatus': 'DRAFT',
      'remark': '', 'receivedAt': null, 'receivedBy': '',
    });
    try {
      await SyncStatusNotifier.instance.trackWrite(
        () => FirebaseFirestore.instance.collection(_rcvCol).doc(docId)
            .update({'receivingLines': lines}),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onAdded?.call();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$itemName added!'), backgroundColor: _kGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (mounted) _err('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: _kRed, behavior: SnackBarBehavior.floating));

  Widget _sugList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: Colors.white, border: Border.all(color: const Color(0xFFe2e8f0)),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          final num  = item['num']  as String? ?? '—';
          final sc   = item['supplierCode'] as String? ?? '';
          final name = item['name'] as String? ?? '';
          final uom  = item['uom']  as String? ?? '';
          return InkWell(
            onTap: () => _select(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F4F8)))),
              child: Row(
                children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(TextSpan(
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c)),
                        children: [
                          TextSpan(text: num),
                          if (sc.isNotEmpty) TextSpan(text: '  ·  $sc',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF718096))),
                        ],
                      )),
                      const SizedBox(height: 2),
                      Text(name + (uom.isNotEmpty ? '  ·  $uom' : ''),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                    ],
                  )),
                  const Icon(Icons.north_west, size: 14, color: Color(0xFFa0aec0)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false, initialChildSize: 0.88, maxChildSize: 0.95,
        builder: (_, ctrl) => Column(
          children: [
            rcvRedHeader(
              title: 'Add Item',
              subtitle: 'Enter item details to add to this receiving record',
              onClose: () => Navigator.pop(context),
            ),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  RcvFloatField(controller: _numCtrl, label: 'Item No.', required: true, onChanged: (v) => _search('num', v)),
                  const SizedBox(height: 4),
                  _sugList(_numSugs),
                  const SizedBox(height: 12),
                  RcvFloatField(controller: _nameCtrl, label: 'Item Name', required: true, onChanged: (v) => _search('name', v)),
                  const SizedBox(height: 4),
                  _sugList(_nameSugs),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: RcvFloatField(controller: _uomCtrl, label: 'UOM')),
                    const SizedBox(width: 12),
                    Expanded(child: RcvFloatField(controller: _scCtrl, label: 'Supplier Code')),
                  ]),
                  const SizedBox(height: 12),
                  RcvFloatField(controller: _qtyCtrl, label: 'Order Qty', required: true, keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: RcvFloatField(controller: _oemCtrl, label: 'OEM #')),
                    const SizedBox(width: 12),
                    Expanded(child: RcvFloatField(controller: _posCtrl, label: 'POS ID')),
                  ]),
                  const SizedBox(height: 28),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.add, size: 16),
                        label: Text(_saving ? 'Saving…' : '+ Add Item',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kRed, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LINE VIEW MODAL
// ═══════════════════════════════════════════════════════════════════════════

void showLineViewModal(BuildContext context, {
  required Map<String, dynamic> rcvData,
  required int lineIdx,
  required bool isBlank,
  required Future<void> Function() onReceive,
  VoidCallback? onEdited,
  VoidCallback? onDeleted,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _LineViewSheet(
      rcvData: rcvData, lineIdx: lineIdx, isBlank: isBlank,
      onReceive: onReceive, onEdited: onEdited, onDeleted: onDeleted,
    ),
  );
}

class _LineViewSheet extends StatelessWidget {
  final Map<String, dynamic> rcvData;
  final int lineIdx;
  final bool isBlank;
  final Future<void> Function() onReceive;
  final VoidCallback? onEdited;
  final VoidCallback? onDeleted;
  const _LineViewSheet({
    required this.rcvData, required this.lineIdx, required this.isBlank,
    required this.onReceive, this.onEdited, this.onDeleted,
  });

  Future<void> _delete(BuildContext ctx, List<Map<String, dynamic>> lines) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove item?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text('Remove "${lines[lineIdx]['itemName'] ?? 'this item'}" from this record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(d, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kRed, foregroundColor: Colors.white),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !ctx.mounted) return;
    final updated = List<Map<String, dynamic>>.from(lines)..removeAt(lineIdx);
    try {
      await SyncStatusNotifier.instance.trackWrite(
        () => FirebaseFirestore.instance.collection(_rcvCol)
            .doc(rcvData['id'] as String).update({'receivingLines': updated}),
      );
      if (ctx.mounted) {
        Navigator.pop(ctx);
        onDeleted?.call();
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Item removed.'), backgroundColor: _kGrey, behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: _kRed, behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = List<Map<String, dynamic>>.from(
        (rcvData['receivingLines'] as List? ?? []).map((l) => Map<String, dynamic>.from(l as Map)));
    if (lineIdx >= lines.length) return const SizedBox.shrink();

    final line   = lines[lineIdx];
    final ls     = line['lineStatus'] as String? ?? 'DRAFT';
    final lc     = _lineColor(ls);
    final status = rcvData['status'] as String? ?? 'DRAFT';
    final isDraft    = ls == 'DRAFT';
    final canReceive = (status == 'INPROG' || status == 'DRAFT') && isDraft;
    final canEdit    = canReceive && isBlank;

    final pQty = (line['poQty'] as num?)?.toInt() ?? 0;
    final rQty = (line['receivedQty'] as num?)?.toInt() ?? 0;
    final diff = rQty - pQty;
    final diffColor = diff == 0 ? _kGreen : diff < 0 ? _kRed : _kAmber;

    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.75, maxChildSize: 0.95,
      builder: (_, ctrl) => Column(
        children: [
          rcvRedHeader(
            title: line['itemName'] as String? ?? '—',
            subtitle: line['itemNum'] as String? ?? '',
            onClose: () => Navigator.pop(context),
          ),
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                rcvRoField('Item No.', line['itemNum'] as String? ?? ''),
                const SizedBox(height: 12),
                rcvRoField('Item Name', line['itemName'] as String? ?? ''),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: rcvRoField('UOM', line['uom'] as String? ?? '')),
                  const SizedBox(width: 12),
                  Expanded(child: rcvRoField('Supplier Code', line['supplierCode'] as String? ?? '')),
                ]),
                const SizedBox(height: 12),
                rcvRoField('Order Qty', '$pQty'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: rcvRoField('OEM #', line['oem'] as String? ?? '')),
                  const SizedBox(width: 12),
                  Expanded(child: rcvRoField('POS ID', line['posId'] as String? ?? '')),
                ]),

                // If already received
                if (!isDraft) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFe2e8f0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          rcvMiniCard('Status', _lineLabels[ls] ?? ls, lc),
                          const SizedBox(width: 10),
                          rcvMiniCard('Rcv Qty', '$rQty', lc),
                          const SizedBox(width: 10),
                          rcvMiniCard('Diff', diff == 0 ? '0' : (diff > 0 ? '+$diff' : '$diff'), diffColor),
                        ]),
                        if ((line['remark'] as String? ?? '').isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text('Remarks: ${line['remark']}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
                        ],
                        if ((line['receivedBy'] as String? ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Received by: ${line['receivedBy']}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Action buttons
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                  if (canEdit) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          showEditLineModal(context,
                              rcvData: rcvData, lineIdx: lineIdx, onSaved: onEdited);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 14),
                        label: const Text('Edit', style: TextStyle(fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4a5568),
                          side: const BorderSide(color: Color(0xFFe2e8f0)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _delete(context, lines),
                        icon: const Icon(Icons.delete_outline, size: 14),
                        label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kRed,
                          side: BorderSide(color: _kRed.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ),
                  ],
                  if (canReceive) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: canEdit ? 1 : 2,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await onReceive();
                        },
                        icon: const Icon(Icons.download_outlined, size: 14),
                        label: const Text('Receive', style: TextStyle(fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kRed, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EDIT LINE MODAL
// ═══════════════════════════════════════════════════════════════════════════

void showEditLineModal(BuildContext context, {
  required Map<String, dynamic> rcvData,
  required int lineIdx,
  VoidCallback? onSaved,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _EditLineSheet(rcvData: rcvData, lineIdx: lineIdx, onSaved: onSaved),
  );
}

class _EditLineSheet extends StatefulWidget {
  final Map<String, dynamic> rcvData;
  final int lineIdx;
  final VoidCallback? onSaved;
  const _EditLineSheet({required this.rcvData, required this.lineIdx, this.onSaved});
  @override
  State<_EditLineSheet> createState() => _EditLineSheetState();
}

class _EditLineSheetState extends State<_EditLineSheet> {
  final _numCtrl  = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _uomCtrl  = TextEditingController();
  final _scCtrl   = TextEditingController();
  final _qtyCtrl  = TextEditingController();
  final _oemCtrl  = TextEditingController();
  final _posCtrl  = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final lines = (widget.rcvData['receivingLines'] as List? ?? []);
    if (widget.lineIdx < lines.length) {
      final l = Map<String, dynamic>.from(lines[widget.lineIdx] as Map);
      _numCtrl.text  = l['itemNum']      as String? ?? '';
      _nameCtrl.text = l['itemName']     as String? ?? '';
      _uomCtrl.text  = l['uom']          as String? ?? '';
      _scCtrl.text   = l['supplierCode'] as String? ?? '';
      _qtyCtrl.text  = '${(l['poQty'] as num?)?.toInt() ?? 0}';
      _oemCtrl.text  = l['oem']          as String? ?? '';
      _posCtrl.text  = l['posId']        as String? ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_numCtrl,_nameCtrl,_uomCtrl,_scCtrl,_qtyCtrl,_oemCtrl,_posCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final itemNum  = _numCtrl.text.trim();
    final itemName = _nameCtrl.text.trim();
    final poQty    = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (itemNum.isEmpty)  { _err('Item No. is required.'); return; }
    if (itemName.isEmpty) { _err('Item Name is required.'); return; }
    if (poQty < 1)        { _err('Order Qty must be at least 1.'); return; }

    setState(() => _saving = true);
    final docId = widget.rcvData['id'] as String;
    final lines = List<Map<String, dynamic>>.from(
        (widget.rcvData['receivingLines'] as List? ?? []).map((l) => Map<String, dynamic>.from(l as Map)));
    lines[widget.lineIdx] = {
      ...lines[widget.lineIdx],
      'itemNum': itemNum, 'itemName': itemName,
      'uom': _uomCtrl.text.trim(), 'supplierCode': _scCtrl.text.trim(),
      'oem': _oemCtrl.text.trim(), 'posId': _posCtrl.text.trim(),
      'poQty': poQty,
    };
    try {
      await SyncStatusNotifier.instance.trackWrite(
        () => FirebaseFirestore.instance.collection(_rcvCol).doc(docId)
            .update({'receivingLines': lines}),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved?.call();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Item updated!'), backgroundColor: _kGreen,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (mounted) _err('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: _kRed, behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false, initialChildSize: 0.88, maxChildSize: 0.95,
        builder: (_, ctrl) => Column(
          children: [
            rcvRedHeader(
              title: 'Edit Item',
              subtitle: 'Update details for this line item',
              onClose: () => Navigator.pop(context),
            ),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  RcvFloatField(controller: _numCtrl, label: 'Item No.', required: true),
                  const SizedBox(height: 12),
                  RcvFloatField(controller: _nameCtrl, label: 'Item Name', required: true),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: RcvFloatField(controller: _uomCtrl, label: 'UOM')),
                    const SizedBox(width: 12),
                    Expanded(child: RcvFloatField(controller: _scCtrl, label: 'Supplier Code')),
                  ]),
                  const SizedBox(height: 12),
                  RcvFloatField(controller: _qtyCtrl, label: 'Order Qty', required: true,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: RcvFloatField(controller: _oemCtrl, label: 'OEM #')),
                    const SizedBox(width: 12),
                    Expanded(child: RcvFloatField(controller: _posCtrl, label: 'POS ID')),
                  ]),
                  const SizedBox(height: 28),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_outlined, size: 16),
                        label: Text(_saving ? 'Saving…' : 'Save Changes',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kRed, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
