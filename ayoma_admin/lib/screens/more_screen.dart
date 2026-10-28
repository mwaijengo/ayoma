import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'notifications_screen.dart';
import 'plans_screen.dart';
import 'settings_screen.dart';
import 'slides_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    void open(Widget page) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const PageHeader(title: 'More'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SectionLabel('Content'),
              _Group(
                children: [
                  _Item(
                    icon: LucideIcons.galleryHorizontal,
                    title: 'Carousel',
                    subtitle: 'Banners at the top of the home screen',
                    onTap: () => open(const SlidesScreen()),
                  ),
                  _Item(
                    icon: LucideIcons.package,
                    title: 'Packages & prices',
                    subtitle: 'Wiki, Mwezi, Miezi 3 and custom packages',
                    onTap: () => open(const PlansScreen()),
                  ),
                ],
              ),
              const SectionLabel('Users'),
              _Group(
                children: [
                  _Item(
                    icon: LucideIcons.bellRing,
                    title: 'Notifications',
                    subtitle: 'Send push messages and renewal reminders',
                    onTap: () => open(const NotificationsScreen()),
                  ),
                ],
              ),
              const SectionLabel('App control'),
              _Group(
                children: [
                  _Item(
                    icon: LucideIcons.slidersHorizontal,
                    title: 'App settings',
                    subtitle: 'Maintenance, force update, WhatsApp, refresh apps',
                    onTap: () => open(const SettingsScreen()),
                  ),
                  _Item(
                    icon: LucideIcons.triangleAlert,
                    title: 'Danger zone',
                    subtitle: 'Downgrade all premium users to free',
                    danger: true,
                    onTap: () => open(const SettingsScreen(scrollToDanger: true)),
                  ),
                ],
              ),
              const SectionLabel('Session'),
              _Group(
                children: [
                  _Item(
                    icon: LucideIcons.server,
                    title: 'Server',
                    subtitle: session.serverUrl,
                  ),
                  _Item(
                    icon: LucideIcons.logOut,
                    title: 'Log out',
                    subtitle: 'Session ends automatically ${formatDate(session.expiresAt)}',
                    danger: true,
                    onTap: session.logout,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 64),
            child,
          ],
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.title, this.subtitle, this.onTap, this.danger = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.green;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(title, style: uStyle(14.5, weight: FontWeight.w700, color: danger ? AppColors.error : AppColors.text)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: uStyle(12, color: AppColors.muted)),
      trailing: onTap == null ? null : const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.faint),
    );
  }
}
