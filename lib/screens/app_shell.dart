import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons_600.dart';

import '../data/catalog.dart';
import '../services/screen_guard.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_restarter.dart';
import 'home_screen.dart';
import 'malipo_screen.dart';
import 'payment_sheet.dart';
import 'player_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

const _settingsTab = 3;

class _AppShellState extends State<AppShell> {
  late final int _tab = AppRestarter.of(context).tab;
  String _category = allCategory;

  Future<void> _play(Channel channel) async {
    final state = AppScope.read(context);
    if (state.canWatch(channel)) {
      await openPlayer(context, channel);
      return;
    }
    final activated = await showPaymentSheet(
      context,
      state.catalog.recommendedPlan,
    );
    if (activated && mounted && state.canWatch(channel)) {
      await openPlayer(context, channel);
    }
  }

  Future<void> _openPlan([Plan? plan]) async {
    ScreenGuard.setSecure(true);
    await showPaymentSheet(
      context,
      plan ?? AppScope.read(context).catalog.recommendedPlan,
    );
    if (mounted) ScreenGuard.setSecure(_tab != _settingsTab);
  }

  /// Every tab change restarts the app on that tab behind the quick splash.
  void _selectTab(int index) {
    if (index == _tab) return;
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    AppRestarter.restart(context, tab: index, quick: true);
  }

  Widget _page() {
    return switch (_tab) {
      1 => MalipoScreen(onSelectPlan: _openPlan),
      2 => SearchScreen(onPlay: _play),
      _settingsTab => SettingsScreen(onSubscribe: _openPlan),
      _ => HomeScreen(
        category: _category,
        onCategory: (value) => setState(() => _category = value),
        onPlay: _play,
        onSubscribe: _openPlan,
        onSeeAll: () => _selectTab(2),
      ),
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ScreenGuard.setSecure(_tab != _settingsTab);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _selectTab(0);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        resizeToAvoidBottomInset: false,
        body: _page(),
        bottomNavigationBar: _BottomNav(index: _tab, onSelect: _selectTab),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    _NavItem('Nyumbani', LucideIcons.house, LucideIcons600.house),
    _NavItem('Malipo', LucideIcons.crown, LucideIcons600.crown),
    _NavItem('Tafuta', LucideIcons.search, LucideIcons600.search),
    _NavItem('Settings', LucideIcons.settings, LucideIcons600.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: 72 + bottom,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: AppColors.navBar,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index ? true : null,
                label: _items[i].label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(i),
                  child: _NavButton(item: _items[i], active: i == index),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active});

  final _NavItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.green : AppColors.navInactive;
    return ExcludeSemantics(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: active ? 1.08 : 1,
            duration: const Duration(milliseconds: 200),
            child: Icon(
              active ? item.activeIcon : item.icon,
              size: 21,
              color: color,
            ),
          ),
          const SizedBox(height: 5),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: uStyle(9, weight: FontWeight.w700, color: color),
            child: Text(item.label),
          ),
        ],
      ),
    );
  }
}
