import 'dart:math';
import 'package:flutter/material.dart';
import 'login.dart';
import 'register.dart';
import 'privacy_policy.dart';
import 'terms_conditions.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  static const _red = Color(0xFFE8001C);

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1a202c), Color(0xFF2d3748), Color(0xFFE8001C)],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(children: [
            // Soft background circles
            Positioned(top: -80, right: -80,
              child: Container(width: 240, height: 240,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06)))),
            Positioned(bottom: 80, left: -100,
              child: Container(width: 280, height: 280,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.04)))),
            Positioned(top: screenH * 0.35, right: -30,
              child: Container(width: 100, height: 100,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.03)))),

            Column(children: [
              const Spacer(flex: 1),

              // ── Animated service scene ──
              SizedBox(
                height: screenH * 0.30,
                child: const _ServiceScene(),
              ),

              const SizedBox(height: 18),

              // ── Branding ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(children: [
                  // Badge pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.22)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Image.asset('assets/img/LOGO_CALTEX.png',
                          width: 15, height: 15, fit: BoxFit.contain),
                      const SizedBox(width: 7),
                      Text('Authorized Caltex Service Partner',
                        style: TextStyle(color: Colors.white.withOpacity(0.92),
                          fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('JA Noble Enterprise Inc.',
                        style: TextStyle(color: Colors.white, fontSize: 28,
                          fontWeight: FontWeight.w900, letterSpacing: 2, height: 1)),
                      const SizedBox(width: 8),
                      Container(width: 1.5, height: 24, color: Colors.white38),
                      const SizedBox(width: 8),
                      Text('Caltex San Pedro',
                        style: TextStyle(color: Colors.white.withOpacity(0.65),
                          fontSize: 13, fontWeight: FontWeight.w600,
                          letterSpacing: 3, height: 1)),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Container(width: 60, height: 3,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.white38, Colors.white70, Colors.white38]),
                      borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 14),
                  Text('Your trusted automotive\nservice partner.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.80),
                      fontSize: 16, fontWeight: FontWeight.w400, height: 1.65)),
                ]),
              ),

              const Spacer(flex: 2),

              // ── Buttons ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(children: [
                  SizedBox(width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const LoginScreen())),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 10,
                        shadowColor: Colors.black.withOpacity(0.3)),
                      child: const Text('Sign In',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                            letterSpacing: 0.3)),
                    )),
                  const SizedBox(height: 11),
                  SizedBox(width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const RegisterScreen())),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        side: BorderSide(color: Colors.white.withOpacity(0.50), width: 1.5)),
                      child: const Text('Create Account',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                            letterSpacing: 0.2)),
                    )),
                ]),
              ),

              const SizedBox(height: 22),

              // Footer links
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                  child: Text('Privacy Policy',
                      style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11,
                        fontWeight: FontWeight.w500, decoration: TextDecoration.underline,
                        decorationColor: Colors.white.withOpacity(0.35)))),
                Text('  ·  ',
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const TermsConditionsScreen())),
                  child: Text('Terms & Conditions',
                      style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11,
                        fontWeight: FontWeight.w500, decoration: TextDecoration.underline,
                        decorationColor: Colors.white.withOpacity(0.35)))),
              ]),
              const SizedBox(height: 18),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  Animated Service Scene Widget
// ═══════════════════════════════════════════════════════
class _ServiceScene extends StatefulWidget {
  const _ServiceScene();
  @override
  State<_ServiceScene> createState() => _ServiceSceneState();
}

class _ServiceSceneState extends State<_ServiceScene>
    with TickerProviderStateMixin {

  late final AnimationController _entryCtrl;   // vehicles drive in
  late final Animation<double> _carEntry;       // 0→1 (right to park)
  late final Animation<double> _truckEntry;     // 0→1 (left to park)

  late final AnimationController _loopCtrl;     // everything that loops
  late final Animation<double> _wheelSpin;
  late final Animation<double> _wrenchBob;
  late final Animation<double> _gearSpin;
  late final Animation<double> _smoke;
  late final Animation<double> _oilDrip;
  late final Animation<double> _spark;
  late final Animation<double> _liftBob;        // lift rises slightly

  @override
  void initState() {
    super.initState();

    // Entry: 2 s ease-out
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000));

    _carEntry = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic);
    _truckEntry = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic);

    _entryCtrl.forward();

    // Loop: 3 s for one full period — everything derives from this
    _loopCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))..repeat();

    _wheelSpin = Tween<double>(begin: 0, end: 2 * pi).animate(_loopCtrl);

    _wrenchBob = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: -0.35, end: 0.35)
          .chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.35, end: -0.35)
          .chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
    ]).animate(_loopCtrl);

    _gearSpin = Tween<double>(begin: 0, end: 2 * pi).animate(_loopCtrl);

    _smoke = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 100),
    ]).animate(_loopCtrl);

    _oilDrip = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0)
          .chain(CurveTween(curve: Curves.easeIn)), weight: 100),
    ]).animate(_loopCtrl);

    _spark = Tween<double>(begin: 0, end: 1).animate(_loopCtrl);

    _liftBob = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0)
          .chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
    ]).animate(_loopCtrl);
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _loopCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_entryCtrl, _loopCtrl]),
      builder: (_, __) => CustomPaint(
        painter: _ScenePainter(
          carEntry: _carEntry.value,
          truckEntry: _truckEntry.value,
          wheelAngle: _wheelSpin.value,
          wrenchAngle: _wrenchBob.value,
          gearAngle: _gearSpin.value,
          smokeT: _smoke.value,
          oilT: _oilDrip.value,
          sparkT: _spark.value,
          liftT: _liftBob.value,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  Painter
// ═══════════════════════════════════════════════════════
class _ScenePainter extends CustomPainter {
  final double carEntry;
  final double truckEntry;
  final double wheelAngle;
  final double wrenchAngle;
  final double gearAngle;
  final double smokeT;
  final double oilT;
  final double sparkT;
  final double liftT;

  const _ScenePainter({
    required this.carEntry, required this.truckEntry,
    required this.wheelAngle, required this.wrenchAngle,
    required this.gearAngle, required this.smokeT,
    required this.oilT, required this.sparkT, required this.liftT,
  });

  // ── Colour palette ────────────────────────────────────
  static const _carBody    = Color(0xFF0F2D54);
  static const _carAccent  = Color(0xFF2563EB);
  static const _truckBody  = Color(0xFF1C1C2E);
  static const _truckAccent= Color(0xFFE8001C);
  static const _glass      = Color(0xFFBAE6FD);
  static const _tyre       = Color(0xFF111827);
  static const _rim        = Color(0xFF94A3B8);
  static const _yellow     = Color(0xFFFBBF24);
  static const _orange     = Color(0xFFF97316);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final gY = h * 0.80;   // ground Y

    // ─ Service bay floor ─
    _drawFloor(canvas, w, h, gY);

    // ─ Vehicle positions (entry animation) ─
    // Car: right → centre-right park at x=0.62
    final carPark  = w * 0.62;
    final carStart = w * 1.55;
    final carCx = carStart - (carStart - carPark) * carEntry;
    final carCy = gY;

    // Truck: left → centre-left park at x=0.28
    final truckPark  = w * 0.28;
    final truckStart = w * -0.60;
    final truckCx = truckStart + (truckPark - truckStart) * truckEntry;
    final truckCy = gY;

    // ─ Background elements ─
    _drawGear(canvas, Offset(w * 0.06, h * 0.14), 18, reverse: false);
    _drawGear(canvas, Offset(w * 0.94, h * 0.18), 14, reverse: true);

    // ─ Smoke (only while moving) ─
    final moving = carEntry < 0.98;
    if (moving) {
      _drawSmoke(canvas, Offset(carCx - 55, carCy - 44), smokeT, small: true);
      _drawSmoke(canvas, Offset(truckCx + 42, truckCy - 70), smokeT);
    }

    // ─ Truck ─
    _drawTruck(canvas, Offset(truckCx, truckCy), w * 0.44, moving: moving);

    // ─ Car ─
    _drawCar(canvas, Offset(carCx, carCy), w * 0.42, moving: moving);

    // ─ Service elements (appear after parking) ─
    final parked = carEntry > 0.92;
    if (parked) {
      _drawHydraulicLift(canvas, Offset(carCx, gY));
      _drawOilDrip(canvas, Offset(carCx - 14, carCy - 8));
      _drawMechanic(canvas, Offset(carCx + w * 0.23, carCy - 12), facing: -1);
      _drawMechanic(canvas, Offset(truckCx - w * 0.12, truckCy - 12), facing: 1);
      _drawSparkles(canvas, Offset(carCx + w * 0.20, carCy - 30));
      _drawSparkles(canvas, Offset(truckCx - w * 0.09, truckCy - 30), offset: 0.5);
    }
  }

  // ─────────────────────────────────────────────────────
  void _drawFloor(Canvas canvas, double w, double h, double gY) {
    // Dark floor strip
    final floorPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.white.withOpacity(0.18), Colors.white.withOpacity(0.08)],
      ).createShader(Rect.fromLTWH(0, gY, w, h - gY));
    canvas.drawRect(Rect.fromLTWH(0, gY, w, h - gY), floorPaint);

    // Red edge stripe
    canvas.drawRect(Rect.fromLTWH(0, gY, w, 3),
        Paint()..color = const Color(0xFFE8001C).withOpacity(0.7));

    // Dashed lane divider
    final dashP = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 1.8;
    for (double x = 0; x < w; x += 36) {
      canvas.drawLine(Offset(x, gY + 10), Offset(x + 18, gY + 10), dashP);
    }
    // Floor reflection gradient
    canvas.drawRect(
      Rect.fromLTWH(0, gY + 3, w, 8),
      Paint()..shader = LinearGradient(
        colors: [Colors.white.withOpacity(0.10), Colors.transparent],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, gY + 3, w, 8)));
  }

  // ─────────────────────────────────────────────────────
  void _drawCar(Canvas canvas, Offset c, double cw, {required bool moving}) {
    final ch = cw * 0.40;
    final cx = c.dx;
    final cy = c.dy;

    // Drop shadow
    _shadow(canvas, Offset(cx, cy + 2), cw * 0.88, 10);

    // ── Lower body ──
    final bodyR = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - cw * 0.5, cy - ch * 0.52, cw, ch * 0.52),
        const Radius.circular(14));

    // Body gradient (dark blue → slightly lighter on top)
    canvas.drawRRect(bodyR, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [const Color(0xFF1E3F6F), _carBody],
      ).createShader(Rect.fromLTWH(cx - cw * 0.5, cy - ch * 0.52, cw, ch * 0.52)));

    // Accent outline
    canvas.drawRRect(bodyR,
      Paint()..color = _carAccent.withOpacity(0.55)
        ..style = PaintingStyle.stroke..strokeWidth = 1.6);

    // Side accent line
    canvas.drawLine(
      Offset(cx - cw * 0.46, cy - ch * 0.25),
      Offset(cx + cw * 0.46, cy - ch * 0.25),
      Paint()..color = _carAccent.withOpacity(0.35)..strokeWidth = 1.2);

    // ── Cabin ──
    final cabin = Path()
      ..moveTo(cx - cw * 0.30, cy - ch * 0.52)
      ..quadraticBezierTo(cx - cw * 0.20, cy - ch * 0.96, cx - cw * 0.06, cy - ch * 0.98)
      ..lineTo(cx + cw * 0.19, cy - ch * 0.98)
      ..quadraticBezierTo(cx + cw * 0.32, cy - ch * 0.94, cx + cw * 0.36, cy - ch * 0.52)
      ..close();
    canvas.drawPath(cabin, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [const Color(0xFF1A3560), _carBody],
      ).createShader(Rect.fromLTWH(cx - cw * 0.3, cy - ch, cw * 0.66, ch * 0.5)));
    canvas.drawPath(cabin, Paint()
      ..color = _carAccent.withOpacity(0.4)
      ..style = PaintingStyle.stroke..strokeWidth = 1.4);

    // ── Windshield & windows ──
    final ws = Path()
      ..moveTo(cx - cw * 0.26, cy - ch * 0.52)
      ..quadraticBezierTo(cx - cw * 0.16, cy - ch * 0.92, cx - cw * 0.04, cy - ch * 0.94)
      ..lineTo(cx + cw * 0.15, cy - ch * 0.94)
      ..quadraticBezierTo(cx + cw * 0.28, cy - ch * 0.90, cx + cw * 0.32, cy - ch * 0.52)
      ..close();
    canvas.drawPath(ws, Paint()..color = _glass.withOpacity(0.38));
    // Glare
    canvas.drawPath(ws, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Colors.white.withOpacity(0.22), Colors.transparent],
      ).createShader(Rect.fromLTWH(cx - cw * 0.26, cy - ch, cw * 0.6, ch * 0.5)));
    // Centre pillar
    canvas.drawLine(
      Offset(cx + 3, cy - ch * 0.94), Offset(cx + 3, cy - ch * 0.52),
      Paint()..color = _carAccent.withOpacity(0.35)..strokeWidth = 1.2);

    // ── Lights ──
    // Headlight glow
    _glow(canvas, Offset(cx + cw * 0.49, cy - ch * 0.26), const Color(0xFFFEF08A), 9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx + cw * 0.44, cy - ch * 0.32, 14, 8), const Radius.circular(4)),
      Paint()..color = const Color(0xFFFEF9C3));
    // Tail light
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - cw * 0.49, cy - ch * 0.32, 10, 8), const Radius.circular(3)),
      Paint()..color = moving
          ? const Color(0xFFE8001C)
          : const Color(0xFFE8001C).withOpacity(0.45));

    // ── Wheels ──
    _wheel(canvas, Offset(cx - cw * 0.3,  cy + 1), cw * 0.135, moving: moving);
    _wheel(canvas, Offset(cx + cw * 0.265, cy + 1), cw * 0.135, moving: moving);
  }

  // ─────────────────────────────────────────────────────
  void _drawTruck(Canvas canvas, Offset c, double tw, {required bool moving}) {
    final th = tw * 0.50;
    final cx = c.dx;
    final cy = c.dy;

    _shadow(canvas, Offset(cx + tw * 0.06, cy + 2), tw * 0.92, 12);

    // ── Trailer ──
    final trailerX = cx - tw * 0.50;
    final trailerW = tw * 0.60;
    final trailerH = th * 0.75;
    final trailerTop = cy - trailerH;

    final trailerR = RRect.fromRectAndRadius(
        Rect.fromLTWH(trailerX, trailerTop, trailerW, trailerH),
        const Radius.circular(8));
    canvas.drawRRect(trailerR, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [const Color(0xFF252535), _truckBody],
      ).createShader(Rect.fromLTWH(trailerX, trailerTop, trailerW, trailerH)));
    canvas.drawRRect(trailerR, Paint()
      ..color = _truckAccent.withOpacity(0.60)
      ..style = PaintingStyle.stroke..strokeWidth = 1.8);

    // Trailer panels (vertical dividers)
    final panelP = Paint()..color = Colors.white.withOpacity(0.07)..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final lx = trailerX + trailerW * (i / 4);
      canvas.drawLine(Offset(lx, trailerTop + 6), Offset(lx, cy - 2), panelP);
    }
    // Horizontal accent stripe
    canvas.drawRect(
      Rect.fromLTWH(trailerX, trailerTop + trailerH * 0.45, trailerW, 3),
      Paint()..color = _truckAccent.withOpacity(0.50));
    // Shine strip top
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(trailerX + 4, trailerTop + 3, trailerW - 8, 4),
          const Radius.circular(2)),
      Paint()..color = Colors.white.withOpacity(0.08));

    // ── Cab ──
    final cabX = cx + tw * 0.09;
    final cabW = tw * 0.41;
    final cabH = th * 0.98;
    final cabTop = cy - cabH;

    final cabR = RRect.fromRectAndRadius(
        Rect.fromLTWH(cabX, cabTop, cabW, cabH),
        const Radius.circular(10));
    canvas.drawRRect(cabR, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [const Color(0xFF2C2C44), _truckBody],
      ).createShader(Rect.fromLTWH(cabX, cabTop, cabW, cabH)));
    canvas.drawRRect(cabR, Paint()
      ..color = _truckAccent.withOpacity(0.65)
      ..style = PaintingStyle.stroke..strokeWidth = 1.8);

    // Windshield
    final wsR = RRect.fromRectAndRadius(
        Rect.fromLTWH(cabX + cabW * 0.10, cabTop + cabH * 0.08,
            cabW * 0.78, cabH * 0.50),
        const Radius.circular(6));
    canvas.drawRRect(wsR, Paint()..color = _glass.withOpacity(0.35));
    canvas.drawRRect(wsR, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Colors.white.withOpacity(0.20), Colors.transparent],
      ).createShader(Rect.fromLTWH(cabX, cabTop, cabW, cabH * 0.6)));
    // Centre divider
    canvas.drawLine(
      Offset(cabX + cabW * 0.50, cabTop + cabH * 0.08),
      Offset(cabX + cabW * 0.50, cabTop + cabH * 0.58),
      Paint()..color = _truckAccent.withOpacity(0.30)..strokeWidth = 1.2);

    // Grille
    final gX = cx + tw * 0.47;
    final gY2 = cy - th * 0.44;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(gX, gY2, 16, 20), const Radius.circular(4)),
      Paint()..color = const Color(0xFF374151));
    for (int g = 0; g < 4; g++) {
      canvas.drawLine(Offset(gX + 2, gY2 + 4 + g * 4),
          Offset(gX + 14, gY2 + 4 + g * 4),
          Paint()..color = const Color(0xFF4B5563)..strokeWidth = 1);
    }

    // Headlight
    _glow(canvas, Offset(gX - 1, cy - th * 0.60), const Color(0xFFFEF08A), 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(gX - 2, cy - th * 0.64, 14, 7), const Radius.circular(3)),
      Paint()..color = const Color(0xFFFEF9C3));

    // Exhaust stack
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx + tw * 0.44, cy - cabH - th * 0.42, 8, th * 0.44),
          const Radius.circular(4)),
      Paint()..color = const Color(0xFF4B5563));

    // Connector hitch
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cabX - 10, cy - th * 0.28, 12, th * 0.28),
          const Radius.circular(3)),
      Paint()..color = const Color(0xFF374151));

    // ── Wheels (4 total) ──
    final wr = tw * 0.088;
    _wheel(canvas, Offset(cx - tw * 0.31, cy + 1), wr, moving: moving, big: true);
    _wheel(canvas, Offset(cx + tw * 0.05, cy + 1), wr, moving: moving, big: true);
    _wheel(canvas, Offset(cx + tw * 0.22, cy + 1), wr, moving: moving, big: true);
    _wheel(canvas, Offset(cx + tw * 0.40, cy + 1), wr, moving: moving, big: true);
  }

  // ─────────────────────────────────────────────────────
  void _wheel(Canvas canvas, Offset c, double r,
      {required bool moving, bool big = false}) {
    // Tyre
    canvas.drawCircle(c, r,
        Paint()..color = _tyre);
    // Rubber tread highlight
    canvas.drawCircle(c, r,
        Paint()..color = const Color(0xFF1F2937)
          ..style = PaintingStyle.stroke..strokeWidth = r * 0.28);

    // Rim
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (moving) canvas.rotate(wheelAngle);

    final rimP = Paint()..color = _rim..strokeWidth = 1.5;
    final spokeCount = big ? 6 : 5;
    for (int i = 0; i < spokeCount; i++) {
      final a = (i / spokeCount) * 2 * pi;
      canvas.drawLine(
        Offset(cos(a) * r * 0.22, sin(a) * r * 0.22),
        Offset(cos(a) * r * 0.82, sin(a) * r * 0.82),
        rimP);
    }
    canvas.restore();

    // Rim ring
    canvas.drawCircle(c, r * 0.80,
        Paint()..color = _rim.withOpacity(0.35)
          ..style = PaintingStyle.stroke..strokeWidth = 1.2);
    // Hub cap
    canvas.drawCircle(c, r * 0.22,
        Paint()..color = const Color(0xFF475569));
    canvas.drawCircle(c, r * 0.10,
        Paint()..color = const Color(0xFF1E293B));
  }

  // ─────────────────────────────────────────────────────
  void _drawHydraulicLift(Canvas canvas, Offset base) {
    final liftH = 8.0 + liftT * 6; // slightly rises
    final p = Paint()
      ..color = Colors.white.withOpacity(0.30)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    // Arms
    canvas.drawLine(Offset(base.dx - 32, base.dy),
        Offset(base.dx - 32, base.dy + liftH), p);
    canvas.drawLine(Offset(base.dx + 32, base.dy),
        Offset(base.dx + 32, base.dy + liftH), p);
    // Base plate
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(base.dx - 42, base.dy + liftH, 84, 5),
          const Radius.circular(3)),
      Paint()..color = Colors.white.withOpacity(0.22));
    // Cylinder highlight
    canvas.drawLine(Offset(base.dx - 32, base.dy + 2),
        Offset(base.dx - 32, base.dy + liftH - 2),
        Paint()..color = Colors.white.withOpacity(0.15)..strokeWidth = 1.5);
  }

  // ─────────────────────────────────────────────────────
  void _drawOilDrip(Canvas canvas, Offset from) {
    final t = oilT;
    if (t <= 0) return;
    final stemLen = t * 22;
    final opacity = t < 0.2 ? t / 0.2 : (t > 0.85 ? (1 - t) / 0.15 : 1.0);

    canvas.drawLine(from, Offset(from.dx, from.dy + stemLen),
        Paint()
          ..color = _orange.withOpacity(opacity * 0.80)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round);

    if (stemLen > 8) {
      final dropC = Offset(from.dx, from.dy + stemLen + 5);
      canvas.drawOval(
        Rect.fromCenter(center: dropC, width: 7, height: 10),
        Paint()..color = _orange.withOpacity(opacity * 0.75));
    }
  }

  // ─────────────────────────────────────────────────────
  void _drawMechanic(Canvas canvas, Offset pos, {required int facing}) {
    final f = facing.toDouble(); // 1=right, -1=left
    final headP = Paint()..color = const Color(0xFFFDE68A);
    final bodyP = Paint()
      ..color = Colors.white.withOpacity(0.88)
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final legP = Paint()
      ..color = const Color(0xFF93C5FD).withOpacity(0.75)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    // Head
    canvas.drawCircle(Offset(pos.dx, pos.dy - 24), 9, headP);
    // Helmet stripe
    canvas.drawArc(Rect.fromCenter(center: Offset(pos.dx, pos.dy - 24), width: 18, height: 18),
        pi * 1.2, pi * 0.6, false,
        Paint()..color = _truckAccent..style = PaintingStyle.stroke..strokeWidth = 2.5);
    // Torso
    canvas.drawLine(Offset(pos.dx, pos.dy - 15), Offset(pos.dx, pos.dy + 10), bodyP);
    // Arm reaching toward vehicle
    canvas.drawLine(Offset(pos.dx, pos.dy - 8),
        Offset(pos.dx - f * 18, pos.dy - 16), bodyP..strokeWidth = 3.5);
    // Legs
    canvas.drawLine(Offset(pos.dx, pos.dy + 10),
        Offset(pos.dx - f * 6, pos.dy + 24), legP);
    canvas.drawLine(Offset(pos.dx, pos.dy + 10),
        Offset(pos.dx + f * 4, pos.dy + 24), legP);

    // Tool (wrench)
    _drawWrench(canvas, Offset(pos.dx - f * 20, pos.dy - 18), flipX: facing > 0);
  }

  void _drawWrench(Canvas canvas, Offset pos, {required bool flipX}) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    if (flipX) canvas.scale(-1, 1);
    canvas.rotate(wrenchAngle);

    // Handle
    canvas.drawLine(const Offset(0, 2), const Offset(0, 22),
        Paint()..color = _yellow..strokeWidth = 4.5..strokeCap = StrokeCap.round);
    // Wrench C-head
    canvas.drawArc(const Rect.fromLTWH(-8, -12, 16, 16),
        pi * 0.1, pi * 1.8, false,
        Paint()..color = _yellow..style = PaintingStyle.stroke
          ..strokeWidth = 4..strokeCap = StrokeCap.round);
    // Second jaw
    canvas.drawLine(const Offset(-8, -4), const Offset(-8, 2),
        Paint()..color = _yellow..strokeWidth = 4..strokeCap = StrokeCap.round);
    canvas.drawLine(const Offset(8, -4), const Offset(8, 2),
        Paint()..color = _yellow..strokeWidth = 4..strokeCap = StrokeCap.round);

    canvas.restore();
  }

  // ─────────────────────────────────────────────────────
  void _drawGear(Canvas canvas, Offset c, double r, {required bool reverse}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(reverse ? -gearAngle : gearAngle);

    final base = Paint()
      ..color = Colors.white.withOpacity(0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(Offset.zero, r, base);
    canvas.drawCircle(Offset.zero, r * 0.42,
        Paint()..color = Colors.white.withOpacity(0.10)
          ..style = PaintingStyle.stroke..strokeWidth = 2);

    const n = 8;
    for (int i = 0; i < n; i++) {
      final a = (i / n) * 2 * pi;
      canvas.drawLine(
        Offset(cos(a) * r * 0.88, sin(a) * r * 0.88),
        Offset(cos(a) * r * 1.32, sin(a) * r * 1.32),
        Paint()..color = Colors.white.withOpacity(0.14)
          ..strokeWidth = 3.5..strokeCap = StrokeCap.round);
    }
    canvas.restore();
  }

  // ─────────────────────────────────────────────────────
  void _drawSmoke(Canvas canvas, Offset from, double t, {bool small = false}) {
    final yOff = -t * 28;
    for (int i = 0; i < 4; i++) {
      final phase = (t + i * 0.22) % 1.0;
      final op = (phase < 0.4 ? phase / 0.4 : (1 - phase) / 0.6).clamp(0.0, 1.0);
      final rad = (small ? 5 : 7) + i * 2.5 + phase * 4;
      final dx = sin(phase * pi * 2 + i) * 4;
      canvas.drawCircle(
        Offset(from.dx + dx, from.dy + yOff - i * 7),
        rad,
        Paint()..color = Colors.white.withOpacity(op * 0.22));
    }
  }

  // ─────────────────────────────────────────────────────
  void _drawSparkles(Canvas canvas, Offset c, {double offset = 0.0}) {
    const positions = [
      Offset(-16, -6), Offset(14, -15), Offset(-6, 10), Offset(18, 5),
      Offset(0, -20), Offset(-12, 18),
    ];
    for (int i = 0; i < positions.length; i++) {
      final phase = (sparkT + i / positions.length + offset) % 1.0;
      final op = (phase < 0.5 ? phase * 2 : (1 - phase) * 2).clamp(0.0, 1.0);
      final sz = 1.8 + phase * 3;
      // Star shape (4-point)
      final sp = c + positions[i];
      canvas.drawCircle(sp, sz,
          Paint()..color = const Color(0xFFFDE047).withOpacity(op * 0.95));
      canvas.drawLine(sp + Offset(0, -sz * 1.8), sp + Offset(0, sz * 1.8),
          Paint()..color = const Color(0xFFFDE047).withOpacity(op * 0.5)
            ..strokeWidth = 1..strokeCap = StrokeCap.round);
      canvas.drawLine(sp + Offset(-sz * 1.8, 0), sp + Offset(sz * 1.8, 0),
          Paint()..color = const Color(0xFFFDE047).withOpacity(op * 0.5)
            ..strokeWidth = 1..strokeCap = StrokeCap.round);
    }
  }

  // ─────────────────────────────────────────────────────
  void _shadow(Canvas canvas, Offset c, double w, double h) {
    canvas.drawOval(
      Rect.fromCenter(center: c, width: w, height: h),
      Paint()..color = Colors.black.withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }

  void _glow(Canvas canvas, Offset c, Color color, double r) {
    canvas.drawCircle(c, r,
        Paint()..color = color.withOpacity(0.30)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.8));
  }

  @override
  bool shouldRepaint(_ScenePainter o) => true;
}
