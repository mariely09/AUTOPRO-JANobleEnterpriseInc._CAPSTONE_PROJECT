import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerScreen extends StatefulWidget {
  final String title;
  final String hint;

  const BarcodeScannerScreen({
    super.key,
    String? title,
    String? hint,
  })  : title = title ?? 'Scan Barcode / QR Code',
        hint = hint ?? 'Point camera at barcode or QR code';

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with SingleTickerProviderStateMixin {
  static const _red = Color(0xFFE8001C);

  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _scanned = false;
  bool _torchOn = false;

  // Animation for the scanning line
  late final AnimationController _animCtrl;
  late final Animation<double> _scanAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue;
    if (raw != null && raw.isNotEmpty) {
      _scanned = true;
      Navigator.pop(context, raw);
    }
  }

  @override
  Widget build(BuildContext context) {
    const overlaySize = 260.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: _red,
        title: Text(widget.title,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Torch toggle
          StatefulBuilder(
            builder: (_, setState) => IconButton(
              icon: Icon(
                _torchOn ? Icons.flash_on : Icons.flash_off,
                color: Colors.white,
              ),
              onPressed: () async {
                await _controller.toggleTorch();
                setState(() => _torchOn = !_torchOn);
              },
            ),
          ),
          // Camera flip
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera feed
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Dark overlay with transparent scan window — four panels around the frame
          LayoutBuilder(
            builder: (_, constraints) {
              final screenW = constraints.maxWidth;
              final screenH = constraints.maxHeight;
              const boxSize = overlaySize;
              final left   = (screenW - boxSize) / 2;
              final top    = (screenH - boxSize) / 2;
              const dark   = Color(0x99000000);
              return Stack(children: [
                // Top
                Positioned(left: 0, top: 0, width: screenW, height: top,
                    child: ColoredBox(color: dark)),
                // Bottom
                Positioned(left: 0, top: top + boxSize, width: screenW,
                    height: screenH - top - boxSize,
                    child: ColoredBox(color: dark)),
                // Left
                Positioned(left: 0, top: top, width: left, height: boxSize,
                    child: ColoredBox(color: dark)),
                // Right
                Positioned(left: left + boxSize, top: top,
                    width: screenW - left - boxSize, height: boxSize,
                    child: ColoredBox(color: dark)),
              ]);
            },
          ),

          // Scan frame corners
          Center(
            child: SizedBox(
              width: overlaySize,
              height: overlaySize,
              child: Stack(children: [
                Positioned(top: 0, left: 0, child: _corner()),
                Positioned(top: 0, right: 0,
                    child: Transform.rotate(angle: 1.5708, child: _corner())),
                Positioned(bottom: 0, left: 0,
                    child: Transform.rotate(angle: -1.5708, child: _corner())),
                Positioned(bottom: 0, right: 0,
                    child: Transform.rotate(angle: 3.1416, child: _corner())),

                // Animated scan line
                AnimatedBuilder(
                  animation: _scanAnim,
                  builder: (_, __) => Positioned(
                    top: _scanAnim.value * (overlaySize - 4),
                    left: 12,
                    right: 12,
                    child: Container(
                      height: 2.5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          _red.withOpacity(0),
                          _red,
                          _red.withOpacity(0),
                        ]),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),

          // Bottom hint
          Positioned(
            bottom: 70,
            left: 0, right: 0,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                    color: const Color(0xB3000000), // black ~70% opacity
                    borderRadius: BorderRadius.circular(24)),
                child: Text(widget.hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 10),
              Text(
                'Code 128 · QR · EAN · UPC supported',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _corner() {
    return Container(
      width: 28, height: 28,
      decoration: const BoxDecoration(
        border: Border(
          top:  BorderSide(color: _red, width: 4),
          left: BorderSide(color: _red, width: 4),
        ),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(5)),
      ),
    );
  }
}
