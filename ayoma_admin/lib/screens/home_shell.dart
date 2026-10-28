import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'channels_screen.dart';
import 'dashboard_screen.dart';
import 'more_screen.dart';
import 'payments_screen.dart';
import 'users_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _items = [
    (label: 'Dashboard', icon: LucideIcons.layoutDashboard),
    (label: 'Channels', icon: LucideIcons.tv),
    (label: 'Users', icon: LucideIcons.users),
    (label: 'Payments', icon: LucideIcons.wallet),
    (label: 'More', icon: LucideIcons.layoutGrid),
  ];

  Widget _page() => switch (_tab) {
    1 => const ChannelsScreen(),
    2 => const UsersScreen(),
    3 => const PaymentsScreen(),
    4 => const MoreScreen(),
    _ => DashboardScreen(onOpenTab: (i) => setState(() => _tab = i)),
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = SafeArea(
      bottom: false,
      child: KeyedSubtree(key: ValueKey(_tab), child: _page()),
    );
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: const Color(0xFF0D1211),
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelType: NavigationRailLabelType.all,
              indicatorColor: AppColors.greenA(0.16),
              selectedIconTheme: const IconThemeData(color: AppColors.green),
              unselectedIconTheme: const IconThemeData(color: AppColors.muted),
              selectedLabelTextStyle: uStyle(11, weight: FontWeight.w700, color: AppColors.green),
              unselectedLabelTextStyle: uStyle(11, weight: FontWeight.w700, color: AppColors.muted),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Icon(LucideIcons.crown, color: AppColors.green),
              ),
              destinations: [
                for (final item in _items)
                  NavigationRailDestination(icon: Icon(item.icon), label: Text(item.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: body),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final item in _items) NavigationDestination(icon: Icon(item.icon), label: item.label),
        ],
      ),
    );
  }
}
