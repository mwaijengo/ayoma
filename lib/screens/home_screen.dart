import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/catalog.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_restarter.dart';
import '../widgets/common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.category,
    required this.onCategory,
    required this.onPlay,
    required this.onSubscribe,
    required this.onSeeAll,
  });

  final String category;
  final ValueChanged<String> onCategory;
  final ValueChanged<Channel> onPlay;
  final VoidCallback onSubscribe;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final channels = AppScope.of(context).catalog.channels;
    final filtered = category == allCategory
        ? channels
        : channels.where((c) => c.category == category).toList();

    return RefreshIndicator(
      color: AppColors.ink,
      backgroundColor: AppColors.green,
      edgeOffset: MediaQuery.paddingOf(context).top,
      onRefresh: () => _refresh(context),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeroCarousel(onPlay: onPlay),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeading(
                    title: 'Chagua chaneli',
                    trailing: Semantics(
                      button: true,
                      child: GestureDetector(
                        onTap: onSeeAll,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Ona zote',
                                style: uStyle(
                                  11,
                                  weight: FontWeight.w700,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                LucideIcons.chevronRight,
                                size: 15,
                                color: AppColors.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _CategoryRow(selected: category, onSelect: onCategory),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 7, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeading(
                    title: category == allCategory
                        ? 'Chaneli zote'
                        : category,
                    trailing: const OnAirLabel(),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: filtered.isEmpty
                        ? const _EmptyCategory()
                        : ChannelGrid(
                            key: ValueKey(category),
                            channels: filtered,
                            onPlay: onPlay,
                          ),
                  ),
                ],
              ),
            ),
            _UpgradeCard(onSubscribe: onSubscribe),
          ],
        ),
      ),
    );
  }

  static Future<void> _refresh(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await Future.wait([
      AppScope.read(context).sync(force: true),
      Future<void>.delayed(const Duration(milliseconds: 350)),
    ]);
    if (context.mounted) AppRestarter.restart(context);
  }
}

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({required this.onPlay});

  final ValueChanged<Channel> onPlay;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  static const _interval = Duration(milliseconds: 5500);
  static const _loopBase = 1000;

  PageController? _pageController;
  Timer? _timer;
  int _index = 0;
  List<Slide> _slides = const [];

  /// Created on first use so the start page matches the server's slides.
  PageController get _controller => _pageController ??= PageController(
    initialPage: _slides.length * _loopBase,
  );

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    _slides = state.catalog.slides;
    final dataSaver = state.dataSaver;
    for (final slide in _slides) {
      precacheImage(
        CachedNetworkImageProvider(
          imageUrlFor(slide.image, dataSaver: dataSaver),
        ),
        context,
        onError: (_, _) {},
      );
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _next());
  }

  void _next() {
    if (_slides.isEmpty || !_controller.hasClients) return;
    _controller.nextPage(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _goTo(int index) {
    final page = _controller.page?.round() ?? 0;
    final current = page % _slides.length;
    _controller.animateToPage(
      page + (index - current),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final catalog = AppScope.of(context).catalog;
    if (_slides.isEmpty) return SizedBox(height: topInset + 16);
    if (_index >= _slides.length) _index = 0;
    return SizedBox(
      height: 440 + topInset,
      child: Stack(
        children: [
          NotificationListener<ScrollStartNotification>(
            onNotification: (notification) {
              if (notification.dragDetails != null) _restartTimer();
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (page) =>
                  setState(() => _index = page % _slides.length),
              itemBuilder: (context, page) {
                final slide = _slides[page % _slides.length];
                final channel = catalog.channelById(slide.channelId);
                return _HeroSlide(
                  slide: slide,
                  onTap: channel == null ? null : () => widget.onPlay(channel),
                  onNext: () {
                    _next();
                    _restartTimer();
                  },
                );
              },
            ),
          ),
          Positioned(
            right: 20,
            bottom: 46,
            child: Row(
              children: [
                for (var i = 0; i < _slides.length; i++)
                  GestureDetector(
                    onTap: () => _goTo(i),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2.5,
                        vertical: 8,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: i == _index ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _index
                              ? AppColors.green
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({required this.slide, required this.onNext, this.onTap});

  final Slide slide;
  final VoidCallback onNext;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          container: true,
          image: true,
          button: onTap != null,
          label: slide.title,
          child: GestureDetector(onTap: onTap, child: NetImage(slide.image)),
        ),
        Positioned(
          left: 22,
          bottom: 34,
          child: CircleIconButton(
            icon: LucideIcons.chevronRight,
            label: 'Inayofuata',
            onTap: onNext,
          ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          for (final item in AppScope.of(context).catalog.categories) ...[
            if (item != allCategory) const SizedBox(width: 8),
            Pressable(
              onTap: () => onSelect(item),
              scale: 0.95,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: item == selected ? AppColors.green : AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: item == selected ? AppColors.green : AppColors.line,
                  ),
                ),
                child: Text(
                  item,
                  style: uStyle(
                    11,
                    weight: FontWeight.w700,
                    color: item == selected ? AppColors.ink : AppColors.text,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(LucideIcons.tv, color: AppColors.faint, size: 28),
          const SizedBox(height: 10),
          Text(
            'Hakuna chaneli hewani kwa sasa',
            style: uStyle(12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Free users see an upgrade prompt; subscribers only see a renewal
/// reminder once less than [_warnWithin] is left.
class _UpgradeCard extends StatefulWidget {
  const _UpgradeCard({required this.onSubscribe});

  final VoidCallback onSubscribe;

  @override
  State<_UpgradeCard> createState() => _UpgradeCardState();
}

class _UpgradeCardState extends State<_UpgradeCard> {
  static const _warnWithin = Duration(days: 3);

  Timer? _revealTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleReveal();
  }

  void _scheduleReveal() {
    _revealTimer?.cancel();
    final wait = AppScope.read(context).timeRemaining - _warnWithin;
    if (wait <= Duration.zero) return;
    // Long timers overflow on web, so re-check at least daily.
    const maxWait = Duration(days: 1);
    _revealTimer = Timer(wait < maxWait ? wait : maxWait, () {
      if (!mounted) return;
      setState(() {});
      _scheduleReveal();
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  static String _format(Duration left) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'siku ${left.inDays} • ${two(left.inHours % 24)}:'
        '${two(left.inMinutes % 60)}:${two(left.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.isSubscribed) {
      return _card(
        leading: const CrownOrb(),
        title: 'Fungua chaneli zote',
        subtitle: 'HD kamili • Bila matangazo • Michezo yote',
        action: 'Lipia',
      );
    }
    if (state.timeRemaining > _warnWithin) return const SizedBox.shrink();
    return CountdownBuilder(
      builder: (context, remaining, _) => _card(
        warning: true,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            LucideIcons.clock3,
            size: 21,
            color: AppColors.ink,
          ),
        ),
        title: 'Umebakiwa na ${_format(remaining)}',
        subtitle: 'Ongezea siku za matumizi sasa kabla hujazimiwa huduma',
        action: 'Ongeza muda',
      ),
    );
  }

  Widget _card({
    required Widget leading,
    required String title,
    required String subtitle,
    required String action,
    bool warning = false,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: warning ? AppColors.red : AppColors.green,
        ),
        color: AppColors.surface,
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: uStyle(12, weight: FontWeight.w700).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: uStyle(9, color: AppColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          Pressable(
            onTap: widget.onSubscribe,
            scale: 0.94,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                action,
                style: uStyle(
                  10,
                  weight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
