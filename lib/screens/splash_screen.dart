import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_restarter.dart';

/// Shows [SplashScreen] over [child] for a moment, then fades it away.
/// The app builds underneath meanwhile, so images start loading early.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  static const duration = Duration(milliseconds: 2600);

  /// Shorter version used as a loader when switching tabs.
  static const quickDuration = Duration(milliseconds: 1500);

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  Timer? _timer;
  late final bool _quick = AppRestarter.of(context).quick;
  bool _visible = true;
  bool _present = true;

  @override
  void initState() {
    super.initState();
    final minimum = Completer<void>();
    _timer = Timer(_quick ? SplashGate.quickDuration : SplashGate.duration, minimum.complete);
    final state = AppScope.maybeRead(context);
    Future.wait([minimum.future, if (state != null) state.waitForCatalog()]).then((_) {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_present)
          AbsorbPointer(
            absorbing: _visible,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: Duration(milliseconds: _quick ? 300 : 450),
              curve: Curves.easeOut,
              onEnd: () => setState(() => _present = false),
              child: SplashScreen(quick: _quick),
            ),
          ),
      ],
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.quick = false});

  final bool quick;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.quick ? 1300 : 2200),
  )..forward();

  late final Animation<double> _logoIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0, 0.45, curve: Curves.easeOutBack),
  );
  late final Animation<double> _taglineIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.5, 0.85, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _pulse.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width * 0.78, 360.0);
    return Semantics(
      label: 'AyomaMax inafunguka',
      excludeSemantics: true,
      child: Material(
        color: Colors.black,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _logoIn,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.7, end: 1.0).animate(_logoIn),
                      child: ScaleTransition(
                        scale: Tween(begin: 1.0, end: 1.035).animate(
                          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                        ),
                        child: Image.asset(
                          'assets/brand/ayoma_logo.png',
                          width: width,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FadeTransition(
                    opacity: _taglineIn,
                    child: Text(
                      'Mpira  •  Filamu  •  Burudani',
                      style: uStyle(
                        12,
                        weight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 56 + MediaQuery.paddingOf(context).bottom,
              child: Center(
                child: SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: AnimatedBuilder(
                      animation: _intro,
                      builder: (context, _) => LinearProgressIndicator(
                        value: _intro.value,
                        minHeight: 3,
                        color: AppColors.red,
                        backgroundColor: const Color(0xFF2A2A2A),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

