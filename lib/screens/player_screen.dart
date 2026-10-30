import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/catalog.dart';
import '../services/api.dart';
import '../services/native_player.dart';
import '../state/app_state.dart';
import 'payment_sheet.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

Future<void> openPlayer(BuildContext context, Channel channel) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => PlayerScreen(channel: channel),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.channel});

  final Channel channel;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat(reverse: true);

  late final AppState _settings = AppScope.read(context);
  bool _playing = true;
  late bool _muted = _settings.startMuted;
  bool _landscape = false;
  bool _fill = true;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  NativePlayer? _player;
  StreamSubscription<PlayerEvent>? _events;
  double? _aspectRatio;
  bool _loading = false;
  bool _buffering = false;
  String? _error;
  bool _needsPayment = false;

  bool get _useNative =>
      NativePlayer.supported &&
      _settings.api != null &&
      widget.channel.id != null;

  bool get _busy =>
      _error == null && (_loading || (_player != null && _buffering));

  /// "Auto" lets the player adapt freely, except on data saver.
  int get _maxHeight => _settings.quality == VideoQuality.auto
      ? (_settings.dataSaver ? VideoQuality.p360.maxHeight : 0)
      : _settings.quality.maxHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (_settings.autoLandscape) _setLandscape(true);
    _scheduleHide();
    if (_useNative) _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _drift.dispose();
    _closePlayer();
    _restorePortrait();
    super.dispose();
  }

  void _restorePortrait() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  }

  /// Rotates back to portrait before the page animates away, so the rest of
  /// the app never shows sideways.
  void _close() {
    _landscape = false;
    _restorePortrait();
    Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _player?.pause();
    } else if (state == AppLifecycleState.resumed && _playing) {
      _player?.play();
    }
  }

  /// [fresh] skips the cached stream details, e.g. after a playback error.
  Future<void> _open({bool fresh = false}) async {
    _closePlayer();
    setState(() {
      _loading = true;
      _error = null;
      _needsPayment = false;
      _aspectRatio = null;
    });
    try {
      final playback = await _settings.api!.playback(
        widget.channel.id!,
        fresh: fresh,
      );
      if (!mounted) return;
      final player = await NativePlayer.open(
        playback,
        maxHeight: _maxHeight,
        muted: _muted,
      );
      if (!mounted) {
        player.dispose();
        return;
      }
      _player = player;
      _events = player.events.listen(_onEvent);
      NativePlayer.keepScreenOn(true);
      setState(() {
        _loading = false;
        _buffering = true;
        _playing = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 402 || e.status == 403 || e.status == 404) _settings.sync(force: true);
      setState(() {
        _loading = false;
        _error = e.message;
        _needsPayment = e.status == 402;
      });
    } on PlatformException catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Imeshindikana kufungua kicheza video. Jaribu tena.';
      });
    }
  }

  void _closePlayer() {
    _events?.cancel();
    _events = null;
    _player?.dispose();
    _player = null;
    NativePlayer.keepScreenOn(false);
  }

  void _onEvent(PlayerEvent event) {
    if (!mounted) return;
    switch (event) {
      case PlayerStateEvent(:final buffering, :final ended):
        setState(() => _buffering = buffering);
        if (ended) _player?.retry();
      case PlayerSizeEvent():
        setState(() => _aspectRatio = event.aspectRatio);
      case PlayerErrorEvent():
        NativePlayer.keepScreenOn(false);
        setState(() => _error = event.message);
    }
  }

  Future<void> _onErrorAction() async {
    if (!_needsPayment) return _open(fresh: true);
    final activated = await showPaymentSheet(
      context,
      _settings.catalog.recommendedPlan,
    );
    if (activated && mounted) _open(fresh: true);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_playing || !_settings.autoHideControls) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _togglePlay() {
    HapticFeedback.selectionClick();
    setState(() => _playing = !_playing);
    if (_playing) {
      _drift.repeat(reverse: true);
      _player?.play();
    } else {
      _drift.stop();
      _player?.pause();
    }
    if (_player != null) NativePlayer.keepScreenOn(_playing);
    _scheduleHide();
  }

  void _toggleLandscape() {
    HapticFeedback.selectionClick();
    setState(() => _setLandscape(!_landscape));
    _scheduleHide();
  }

  void _setLandscape(bool value) {
    _landscape = value;
    SystemChrome.setPreferredOrientations(
      value
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final padding = MediaQuery.paddingOf(context);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final edge = isLandscape ? 12.0 : 18.0;

    return PopScope(
      canPop: false,
      // Back leaves landscape first; a second back closes the player.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_landscape) {
          _toggleLandscape();
        } else {
          _close();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_player != null && _aspectRatio != null)
                isLandscape && _fill
                    // Stretches to every edge so nothing is cropped.
                    ? SizedBox.expand(
                        child: Texture(textureId: _player!.textureId),
                      )
                    : Center(
                        child: AspectRatio(
                          aspectRatio: _aspectRatio!,
                          child: Texture(textureId: _player!.textureId),
                        ),
                      )
              else
                AnimatedBuilder(
                  animation: _drift,
                  builder: (_, child) => Transform.scale(
                    scale: 1 + 0.06 * Curves.easeInOut.transform(_drift.value),
                    child: child,
                  ),
                  child: NetImage(channel.image),
                ),
              AnimatedOpacity(
                opacity: _playing ? 0 : 0.35,
                duration: const Duration(milliseconds: 250),
                child: const ColoredBox(color: Colors.black),
              ),
              AnimatedOpacity(
                opacity: _controlsVisible || _player == null ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: const Column(
                  children: [
                    ColoredBox(
                      color: Colors.black,
                      child: SizedBox(height: 96, width: double.infinity),
                    ),
                    Spacer(),
                    ColoredBox(
                      color: Colors.black,
                      child: SizedBox(height: 140, width: double.infinity),
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            edge + padding.left,
                            edge + padding.top,
                            edge + padding.right,
                            edge,
                          ),
                          child: Row(
                            children: [
                              CircleIconButton(
                                icon: LucideIcons.chevronLeft,
                                iconSize: 24,
                                label: 'Funga',
                                onTap: _close,
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      channel.name,
                                      style: uStyle(
                                        14,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const LiveDot(size: 5, ring: false),
                                        const SizedBox(width: 5),
                                        Text(
                                          'MUBASHARA',
                                          style: uStyle(
                                            9,
                                            color: const Color(0xFFD1D5D3),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.white,
                                  ),
                                ),
                                child: Text(
                                  AppScope.of(context).effectiveQuality.badge,
                                  style: uStyle(8, weight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!_busy && _error == null)
                        Center(
                          child: Pressable(
                            onTap: _togglePlay,
                            scale: 0.92,
                            semanticLabel: _playing ? 'Simamisha' : 'Cheza',
                            child: Container(
                              width: 66,
                              height: 66,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                                border: Border.all(color: Colors.white),
                              ),
                                  child: _playing
                                      ? Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            _bar(),
                                            const SizedBox(width: 7),
                                            _bar(),
                                          ],
                                        )
                                      : const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 36,
                                          color: Colors.white,
                                        ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            edge + padding.left,
                            edge,
                            edge + padding.right,
                            (isLandscape ? 14 : 22) + padding.bottom,
                          ),
                          child: Column(
                            children: [
                              Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: AppColors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setState(() => _muted = !_muted);
                                      _player?.setMuted(_muted);
                                      _scheduleHide();
                                    },
                                    child: Row(
                                      children: [
                                        Icon(
                                          _muted
                                              ? LucideIcons.volumeX
                                              : LucideIcons.volume2,
                                          size: 21,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 7),
                                        Text(
                                          'MUBASHARA',
                                          style: uStyle(
                                            9,
                                            weight: FontWeight.w700,
                                            color: const Color(0xFFFF5A52),
                                            letterSpacing: 0.45,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  if (isLandscape) ...[
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        setState(() => _fill = !_fill);
                                        _scheduleHide();
                                      },
                                      child: Row(
                                        children: [
                                          Icon(
                                            _fill
                                                ? LucideIcons.shrink
                                                : LucideIcons.expand,
                                            size: 21,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 7),
                                          Text(
                                            _fill
                                                ? 'Picha nzima'
                                                : 'Jaza skrini',
                                            style: uStyle(9),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 22),
                                  ],
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _toggleLandscape,
                                    child: Row(
                                      children: [
                                        Icon(
                                          _landscape
                                              ? LucideIcons.minimize2
                                              : LucideIcons.maximize2,
                                          size: 21,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 7),
                                        Text(
                                          _landscape
                                              ? 'Skrini wima'
                                              : 'Skrini ya mlalo',
                                          style: uStyle(9),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_busy)
                const IgnorePointer(
                  child: Center(
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.green,
                      ),
                    ),
                  ),
                ),
              if (_error != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 340),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _needsPayment
                                    ? LucideIcons.crown
                                    : LucideIcons.triangleAlert,
                                size: 34,
                                color: _needsPayment
                                    ? AppColors.green
                                    : const Color(0xFFFF5A52),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: uStyle(12, height: 1.6),
                              ),
                              const SizedBox(height: 16),
                              AppButton(
                                label: _needsPayment
                                    ? 'Lipia sasa'
                                    : 'Jaribu tena',
                                icon: _needsPayment
                                    ? LucideIcons.crown
                                    : LucideIcons.refreshCw,
                                onTap: _onErrorAction,
                              ),
                            ],
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

  Widget _bar() => Container(
    width: 5,
    height: 23,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(3),
    ),
  );
}
