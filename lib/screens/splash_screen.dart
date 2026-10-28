import 'dart:async';
import 'dart:math' as math;

import 'package:lucide_icons_flutter/lucide_icons.dart';
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
  static const _brand = 'AyomaMax';
  static const _accentFrom = 5;

  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat();

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.quick ? 1300 : 2200),
  )..forward();

  late final Animation<double> _iconsIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0, 0.3, curve: Curves.easeOutBack),
  );
  late final Animation<double> _crownIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.22, 0.42, curve: Curves.elasticOut),
  );
  late final Animation<double> _typing = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.3, 0.72),
  );
  late final Animation<double> _taglineIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.72, 0.95, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _bounce.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AyomaMax inafunguka',
      excludeSemantics: true,
      child: Material(
        color: AppColors.bg,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.25),
              radius: 0.9,
              colors: [Color(0x26A8EF3A), Color(0x00A8EF3A)],
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _iconsIn,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _BouncingIcon(
                            animation: _bounce,
                            phase: 0,
                            spin: true,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.green,
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x55A8EF3A),
                                    blurRadius: 24,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.sports_soccer_rounded,
                                size: 44,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 26),
                          _BouncingIcon(
                            animation: _bounce,
                            phase: 0.5,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppColors.greenA(0.45),
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                LucideIcons.clapperboard,
                                size: 30,
                                color: AppColors.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    AnimatedBuilder(
                      animation: Listenable.merge([_intro, _bounce]),
                      builder: (context, _) => _brandLine(),
                    ),
                    const SizedBox(height: 12),
                    FadeTransition(
                      opacity: _taglineIn,
                      child: Text(
                        'Mpira  •  Filamu  •  Burudani',
                        style: uStyle(
                          11,
                          weight: FontWeight.w700,
                          color: AppColors.muted,
                          letterSpacing: 0.6,
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
                          color: AppColors.green,
                          backgroundColor: const Color(0x14FFFFFF),
                        ),
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

  Widget _brandLine() {
    final typed = (_typing.value * _brand.length).round();
    final typingDone = typed >= _brand.length;
    final cursorOn = !typingDone || _bounce.value < 0.5;
    final style = uStyle(
      34,
      weight: FontWeight.w800,
      letterSpacing: -1.2,
      height: 1,
    );

    Widget word(int count) => Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: _brand.substring(0, math.min(count, _accentFrom))),
          if (count > _accentFrom)
            TextSpan(
              text: _brand.substring(_accentFrom, count),
              style: const TextStyle(color: AppColors.green),
            ),
        ],
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: _crownIn.value,
          child: const Icon(
            LucideIcons.crown,
            size: 30,
            color: AppColors.green,
          ),
        ),
        const SizedBox(width: 10),
        // The invisible full word keeps the line from shifting while typing.
        Stack(
          children: [
            Opacity(opacity: 0, child: word(_brand.length)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                word(typed),
                const SizedBox(width: 3),
                Opacity(
                  opacity: cursorOn ? 1 : 0,
                  child: Container(
                    width: 3,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.green,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Hops on a gravity-like arc with a squash on landing and a shadow below.
class _BouncingIcon extends StatelessWidget {
  const _BouncingIcon({
    required this.animation,
    required this.phase,
    required this.child,
    this.spin = false,
  });

  static const _height = 38.0;

  final Animation<double> animation;
  final double phase;
  final bool spin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72 + _height + 14,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final t = (animation.value + phase) % 1.0;
          final lift = 4 * t * (1 - t);
          final squash = lift < 0.12 ? (0.12 - lift) / 0.12 : 0.0;
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: 46 * (1 - lift * 0.45),
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Color.fromRGBO(0, 0, 0, 0.55 - lift * 0.35),
                ),
              ),
              Positioned(
                bottom: 8 + lift * _height,
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.diagonal3Values(
                    1 + squash * 0.12,
                    1 - squash * 0.14,
                    1,
                  ),
                  child: Transform.rotate(
                    angle: spin ? animation.value * 2 * math.pi : 0,
                    child: child,
                  ),
                ),
              ),
            ],
          );
        },
        child: child,
      ),
    );
  }
}
