import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:material_ui/material_ui.dart';

/// How the app should come back after [AppRestarter.restart].
class RestartInfo {
  const RestartInfo({this.tab = 0, this.quick = false});

  /// Bottom navigation tab to open.
  final int tab;

  /// Use the short splash, as a loader between tabs.
  final bool quick;
}

/// Rebuilds everything below it from scratch, which also replays the splash.
class AppRestarter extends StatefulWidget {
  const AppRestarter({super.key, required this.child});

  final Widget child;

  static void restart(BuildContext context, {int tab = 0, bool quick = false}) {
    context.findAncestorStateOfType<_AppRestarterState>()?._restart(
      RestartInfo(tab: tab, quick: quick),
    );
  }

  static RestartInfo of(BuildContext context) {
    return context.findAncestorStateOfType<_AppRestarterState>()?._info ??
        const RestartInfo();
  }

  /// Wipes downloaded and decoded images, then restarts the app.
  /// Subscription, device ID and settings are kept.
  static Future<void> clearCacheAndRestart(BuildContext context) async {
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {
      // The memory cache below is still cleared and the app still restarts.
    }
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    if (context.mounted) restart(context);
  }

  @override
  State<AppRestarter> createState() => _AppRestarterState();
}

class _AppRestarterState extends State<AppRestarter> {
  Key _key = UniqueKey();
  RestartInfo _info = const RestartInfo();

  void _restart(RestartInfo info) => setState(() {
    _info = info;
    _key = UniqueKey();
  });

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
