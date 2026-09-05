import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SyncStatusNotifier — app-wide singleton that tracks:
//   • online/offline state  (periodic DNS ping, every 5 s)
//   • pending write count   (incremented on every Firestore write, cleared
//                            when the write resolves)
//   • offline write events  (stream so any widget can show a toast)
// ═══════════════════════════════════════════════════════════════════════════
class SyncStatusNotifier extends ChangeNotifier {
  SyncStatusNotifier._();
  static final SyncStatusNotifier instance = SyncStatusNotifier._();

  bool _online  = true;
  int  _pending = 0;

  bool get online  => _online;
  int  get pending => _pending;
  bool get synced  => _online && _pending == 0;

  // Stream that emits whenever a write is queued while offline.
  // Widgets can listen to show a "Saved offline" toast.
  final _offlineWriteController = StreamController<void>.broadcast();
  Stream<void> get onOfflineWrite => _offlineWriteController.stream;

  Timer? _pingTimer;

  void init() {
    if (kIsWeb) return;
    _pingTimer?.cancel();
    _pingOnce();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pingOnce());
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _offlineWriteController.close();
    super.dispose();
  }

  Future<void> _pingOnce() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      final nowOnline = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
      if (nowOnline != _online) {
        _online = nowOnline;
        notifyListeners();
      }
    } catch (_) {
      if (_online) {
        _online = false;
        notifyListeners();
      }
    }
  }

  void markPending() {
    _pending++;
    notifyListeners();
  }

  void markResolved() {
    if (_pending > 0) {
      _pending--;
      notifyListeners();
    }
  }

  /// Wraps a Firestore write, tracking pending state.
  /// If offline at the time of the write, fires [onOfflineWrite] so
  /// listeners can show a "Saved offline — will sync when connected" toast.
  Future<T> trackWrite<T>(Future<T> Function() writeFn) async {
    final wasOffline = !_online;
    markPending();
    try {
      final result = await writeFn();
      markResolved();
      // Firestore resolves offline writes optimistically (local cache).
      // Notify listeners so they can show an offline-save confirmation.
      if (wasOffline && !kIsWeb) {
        _offlineWriteController.add(null);
      }
      return result;
    } catch (e) {
      markResolved();
      rethrow;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// OfflineSaveListener — wraps a child widget and shows a SnackBar whenever
// a write completes while the device is offline.
// Drop this at the root of any Scaffold body that performs writes.
//
// Usage:
//   body: OfflineSaveListener(child: MyBody()),
// ═══════════════════════════════════════════════════════════════════════════
class OfflineSaveListener extends StatefulWidget {
  final Widget child;
  const OfflineSaveListener({super.key, required this.child});

  @override
  State<OfflineSaveListener> createState() => _OfflineSaveListenerState();
}

class _OfflineSaveListenerState extends State<OfflineSaveListener> {
  StreamSubscription<void>? _sub;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _wasOffline = !SyncStatusNotifier.instance.online;

    // Show toast whenever a write is queued while offline
    _sub = SyncStatusNotifier.instance.onOfflineWrite.listen((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.cloud_off_outlined, color: Colors.white, size: 16),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Saved locally — will sync when back online.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ]),
        backgroundColor: const Color(0xFF92400E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    });

    // Show "back online" toast when connectivity is restored
    SyncStatusNotifier.instance.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    if (!mounted) return;
    final notifier = SyncStatusNotifier.instance;
    if (_wasOffline && notifier.online) {
      // Just came back online
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.cloud_done_outlined, color: Colors.white, size: 16),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Back online — changes are being synced.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ]),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
    _wasOffline = !notifier.online;
  }

  @override
  void dispose() {
    _sub?.cancel();
    SyncStatusNotifier.instance.removeListener(_onSyncChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ═══════════════════════════════════════════════════════════════════════════
// SyncIndicator — small AppBar action widget.
// Shows:
//   🔴  Offline (N) — offline with pending writes
//   🔄  Syncing…   — online, pending writes
//   🟢  Synced     — online, nothing pending
// Tap → tooltip SnackBar with details.
// ═══════════════════════════════════════════════════════════════════════════
class SyncIndicator extends StatefulWidget {
  const SyncIndicator({super.key});

  @override
  State<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends State<SyncIndicator>
    with SingleTickerProviderStateMixin {
  final _notifier = SyncStatusNotifier.instance;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _notifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    _notifier.removeListener(_rebuild);
    _pulse.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _showStatus() {
    final msg = _notifier.synced
        ? '✅  All data synced'
        : _notifier.online
            ? '🔄  Syncing ${_notifier.pending} pending write(s)…'
            : '📴  Offline — ${_notifier.pending} change(s) will sync when back online';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      backgroundColor: _notifier.synced ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

    final synced  = _notifier.synced;
    final online  = _notifier.online;
    final pending = _notifier.pending;

    return GestureDetector(
      onTap: _showStatus,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            final opacity = synced ? 1.0 : 0.5 + 0.5 * _pulse.value;
            return Opacity(
              opacity: opacity,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: synced
                      ? Colors.green.withOpacity(0.25)
                      : Colors.red.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: synced ? Colors.green.shade300 : Colors.red.shade300,
                    width: 1,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    synced
                        ? Icons.cloud_done_outlined
                        : online
                            ? Icons.sync_outlined
                            : Icons.cloud_off_outlined,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    synced
                        ? 'Synced'
                        : online
                            ? 'Syncing…'
                            : 'Offline${pending > 0 ? ' ($pending)' : ''}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

