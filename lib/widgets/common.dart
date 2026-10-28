import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/catalog.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Rewrites Unsplash URLs to a lighter variant when data saver is on.
String imageUrlFor(String url, {required bool dataSaver}) {
  if (!dataSaver) return url;
  return url
      .replaceAll(RegExp(r'w=\d+'), 'w=480')
      .replaceAll(RegExp(r'q=\d+'), 'q=55');
}

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final dataSaver = AppScope.of(context).dataSaver;
    return CachedNetworkImage(
      imageUrl: imageUrlFor(url, dataSaver: dataSaver),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      filterQuality: FilterQuality.high,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, _) => const ColoredBox(color: AppColors.surface2),
      errorWidget: (_, _, _) => const ColoredBox(
        color: AppColors.surface2,
        child: Center(
          child: Icon(LucideIcons.film, color: AppColors.faint, size: 26),
        ),
      ),
    );
  }
}

/// Tap target that gently scales down while pressed.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.semanticLabel,
    this.onHighlightChanged,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final String? semanticLabel;
  final ValueChanged<bool>? onHighlightChanged;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down == value) return;
    setState(() => _down = value);
    widget.onHighlightChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => _set(true),
        onTapUp: widget.onTap == null ? null : (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.iconSize = 20,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      semanticLabel: label,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xB8141918),
          border: Border.all(color: AppColors.line),
        ),
        child: Icon(icon, size: iconSize, color: AppColors.text),
      ),
    );
  }
}

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.ghost = false,
    this.expand = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool ghost;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final fg = ghost ? AppColors.text : AppColors.ink;
    return Pressable(
      onTap: loading ? null : onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: ghost ? AppColors.surface2 : AppColors.green,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            else ...[
              if (icon != null) ...[
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uStyle(13, weight: FontWeight.w800, color: fg),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LiveDot extends StatelessWidget {
  const LiveDot({super.key, this.size = 7, this.ring = true});

  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.red,
        boxShadow: ring
            ? const [BoxShadow(color: Color(0x2BFF493F), spreadRadius: 4)]
            : null,
      ),
    );
  }
}

class CrownOrb extends StatelessWidget {
  const CrownOrb({super.key, this.size = 40, this.iconSize = 22});

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.greenA(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(LucideIcons.crown, size: iconSize, color: AppColors.green),
    );
  }
}

class UToggle extends StatelessWidget {
  const UToggle({super.key, required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 38,
      height: 22,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? AppColors.green : AppColors.toggleOff,
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? AppColors.ink : AppColors.toggleKnobOff,
          ),
        ),
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    required this.height,
    required this.track,
  });

  final double value;
  final double height;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: height,
        color: track,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => FractionallySizedBox(
            widthFactor: v,
            heightFactor: 1,
            child: const ColoredBox(color: AppColors.green),
          ),
        ),
      ),
    );
  }
}

/// Rebuilds every frame with the live time left on the subscription.
class CountdownBuilder extends StatefulWidget {
  const CountdownBuilder({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    Duration remaining,
    double fraction,
  )
  builder;

  @override
  State<CountdownBuilder> createState() => _CountdownBuilderState();
}

class _CountdownBuilderState extends State<CountdownBuilder>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);

  void _tick(Duration _) {
    final state = AppScope.read(context);
    if (state.expiresAt == null) {
      state.checkExpiry();
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = AppScope.of(context).expiresAt != null;
    if (active && !_ticker.isActive) _ticker.start();
    if (!active && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    var remaining = state.timeRemaining;
    if (remaining.isNegative) remaining = Duration.zero;
    return widget.builder(context, remaining, state.fractionFor(remaining));
  }
}

/// Days, hours, minutes, seconds and milliseconds as a row of tiles.
class CountdownUnits extends StatelessWidget {
  const CountdownUnits({
    super.key,
    required this.remaining,
    this.compact = false,
  });

  final Duration remaining;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    String two(int v) => v.toString().padLeft(2, '0');
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final seconds = remaining.inSeconds % 60;
    final units = [
      (two(days), 'SIKU'),
      (two(hours), 'SAA'),
      (two(minutes), 'DAKIKA'),
      (two(seconds), 'SEKUNDE'),
      (
        (remaining.inMilliseconds % 1000).toString().padLeft(3, '0'),
        'MILISEKUNDE',
      ),
    ];
    return Semantics(
      label:
          'Zimebaki siku $days, saa $hours, dakika $minutes, sekunde $seconds',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < units.length; i++) ...[
            if (i > 0) SizedBox(width: compact ? 5 : 6),
            Expanded(
              flex: i == units.length - 1 ? 5 : 4,
              child: _CountdownTile(
                value: units[i].$1,
                label: units[i].$2,
                compact: compact,
                highlight: i == units.length - 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountdownTile extends StatelessWidget {
  const _CountdownTile({
    required this.value,
    required this.label,
    required this.compact,
    required this.highlight,
  });

  final String value;
  final String label;
  final bool compact;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(4, compact ? 9 : 11, 4, compact ? 7 : 9),
      decoration: BoxDecoration(
        color: highlight ? AppColors.greenA(0.07) : const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: highlight ? AppColors.greenA(0.2) : AppColors.line,
        ),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: uStyle(
                compact ? 18 : 22,
                weight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1,
                color: highlight ? AppColors.green : AppColors.text,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: uStyle(
                6.5,
                weight: FontWeight.w800,
                color: AppColors.muted,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card with a soft radial green glow layered over a solid or gradient fill.
class GlowCard extends StatelessWidget {
  const GlowCard({
    super.key,
    required this.child,
    required this.radius,
    required this.borderColor,
    required this.glowCenter,
    required this.glowRadius,
    required this.glowAlpha,
    this.color,
    this.gradient,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final double radius;
  final Color borderColor;
  final Alignment glowCenter;
  final double glowRadius;
  final double glowAlpha;
  final Color? color;
  final Gradient? gradient;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        gradient: gradient,
        borderRadius: shape,
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: shape,
          border: Border.all(color: borderColor),
          gradient: RadialGradient(
            center: glowCenter,
            radius: glowRadius,
            colors: [AppColors.greenA(glowAlpha), AppColors.greenA(0)],
          ),
        ),
        child: child,
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.trailing,
    this.margin = const EdgeInsets.fromLTRB(0, 11, 0, 14),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: uStyle(17, weight: FontWeight.w800, letterSpacing: -0.3),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class OnAirLabel extends StatelessWidget {
  const OnAirLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LiveDot(),
        const SizedBox(width: 7),
        Text(
          'Hewani',
          style: uStyle(
            10,
            weight: FontWeight.w700,
            color: AppColors.muted,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xC8080B0A),
        borderRadius: BorderRadius.circular(7),
      ),
      child: child,
    );
  }
}

class ChannelCard extends StatefulWidget {
  const ChannelCard({super.key, required this.channel, required this.onPlay});

  final Channel channel;
  final VoidCallback onPlay;

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final pillStyle = uStyle(8, weight: FontWeight.w800, letterSpacing: 0.48);
    return Pressable(
      onTap: widget.onPlay,
      semanticLabel: 'Tazama ${channel.name}',
      onHighlightChanged: (value) {
        if (value) AppScope.read(context).prefetchPlayback(channel);
        setState(() => _pressed = value);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 0.76,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _pressed ? AppColors.green : AppColors.cardBorder,
                  width: 1.4,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedScale(
                      scale: _pressed ? 1.04 : 1,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                      child: NetImage(channel.image),
                    ),
                    Positioned(
                      top: 9,
                      left: 9,
                      right: 9,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _Pill(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const LiveDot(size: 5, ring: false),
                                    const SizedBox(width: 4),
                                    Text('MUBASHARA', style: pillStyle),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (channel.premium) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: _Pill(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        LucideIcons.crown,
                                        size: 12,
                                        color: AppColors.green,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'MALIPO',
                                        style: pillStyle.copyWith(
                                          color: AppColors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Center(
                      child: AnimatedOpacity(
                        opacity: _pressed ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xB8080C0A),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 22,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 9, 2, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uStyle(12, weight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  channel.category,
                  style: uStyle(9, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChannelGrid extends StatelessWidget {
  const ChannelGrid({super.key, required this.channels, required this.onPlay});

  final List<Channel> channels;
  final ValueChanged<Channel> onPlay;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < channels.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 12));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ChannelCard(
                key: ValueKey(channels[i].name),
                channel: channels[i],
                onPlay: () => onPlay(channels[i]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: i + 1 < channels.length
                  ? ChannelCard(
                      key: ValueKey(channels[i + 1].name),
                      channel: channels[i + 1],
                      onPlay: () => onPlay(channels[i + 1]),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }
    return Column(children: rows);
  }
}

void showAppToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface2,
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: const BorderSide(color: AppColors.line),
        ),
        duration: const Duration(seconds: 2),
        content: Text(message, style: uStyle(12, weight: FontWeight.w700)),
      ),
    );
}
