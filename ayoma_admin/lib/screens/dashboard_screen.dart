import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'notifications_screen.dart';
import 'payments_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final content = Column(
      children: [
        PageHeader(
          title: 'Dashboard',
          subtitle: 'Session ends ${formatDate(session.expiresAt)}',
          actions: [
            IconButton(
              tooltip: 'Log out',
              onPressed: session.logout,
              icon: const Icon(LucideIcons.logOut, size: 20, color: AppColors.muted),
            ),
          ],
        ),
        Expanded(
          child: AsyncList<DashboardData>(
            load: session.api.dashboard,
            builder: (context, d, reload) => [
              _RevenueHero(data: d),
              const SizedBox(height: 12),
              _StatGrid(
                items: [
                  (LucideIcons.users, 'Users', '${d['usersTotal']}', '+${d['usersToday']} today', AppColors.text),
                  (LucideIcons.crown, 'Premium', '${d['premiumActive']}', 'active now', AppColors.green),
                  (LucideIcons.clock3, 'Expiring', '${d['expiringSoon']}', 'within 3 days', AppColors.amber),
                  (LucideIcons.userX, 'Expired', '${d['expired']}', 'need renewal', AppColors.error),
                  (LucideIcons.activity, 'Online', '${d['onlineNow']}', 'last 10 min', AppColors.blue),
                  (LucideIcons.tv, 'Channels', '${d['channelsActive']}', 'active', AppColors.text),
                ],
              ),
              const SectionLabel('Quick actions'),
              _QuickActions(onOpenTab: onOpenTab, onChanged: reload),
              SectionLabel(
                'Recent payments',
                trailing: TextButton(onPressed: () => onOpenTab(3), child: const Text('See all')),
              ),
              if (d.recentPayments.isEmpty)
                const Panel(
                  child: EmptyState(icon: LucideIcons.wallet, title: 'No payments yet'),
                )
              else
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final p in d.recentPayments) PaymentTile(payment: p, onChanged: reload),
                    ],
                  ),
                ),
              const SizedBox(height: 64),
            ],
          ),
        ),
      ],
    );
    return Stack(
      children: [
        Positioned.fill(child: content),
        Positioned(
          right: 20,
          bottom: 30,
          child: FloatingActionButton(
            heroTag: 'dashboard_send_notification',
            tooltip: 'Send notification',
            backgroundColor: AppColors.green,
            foregroundColor: AppColors.bg,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            child: const Icon(LucideIcons.bellPlus, size: 24),
          ),
        ),
      ],
    );
  }
}

class _RevenueHero extends StatelessWidget {
  const _RevenueHero({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final days = data.last7Days;
    final maxRevenue = days.fold<int>(1, (m, d) => d.revenue > m ? d.revenue : m);
    const weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Panel(
      padding: const EdgeInsets.all(18),
      borderColor: AppColors.greenA(0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.trendingUp, size: 16, color: AppColors.green),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "TODAY'S REVENUE",
                  overflow: TextOverflow.ellipsis,
                  style: uStyle(11.5, weight: FontWeight.w800, color: AppColors.green, letterSpacing: 1.1),
                ),
              ),
              if (data['paymentsPending'] > 0)
                Pill('${data['paymentsPending']} pending', color: AppColors.amber, icon: LucideIcons.hourglass),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatTzs(data['revenueToday']), style: uStyle(34, weight: FontWeight.w800, letterSpacing: -1)),
          ),
          Text(
            '${data['paymentsToday']} payment${data['paymentsToday'] == 1 ? '' : 's'} today',
            style: uStyle(13, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, d) in days.indexed)
                  Expanded(
                    child: Tooltip(
                      message: '${formatDate(d.day, time: false)}: ${formatTzs(d.revenue)}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: FractionallySizedBox(
                                heightFactor: (d.revenue / maxRevenue).clamp(0.04, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: i == days.length - 1 ? AppColors.green : AppColors.greenA(0.3),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              weekday[d.day.weekday - 1],
                              style: uStyle(10.5, weight: FontWeight.w700, color: AppColors.dim),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'This month', value: formatTzs(data['revenueMonth']))),
              Expanded(child: _MiniStat(label: 'All time', value: formatTzs(data['revenueTotal']))),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: uStyle(12, color: AppColors.dim)),
        const SizedBox(height: 2),
        Text(value, style: uStyle(15, weight: FontWeight.w800)),
      ],
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.items});

  final List<(IconData, String, String, String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 640 ? 3 : 2;
        final width = (c.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (icon, label, value, hint, color) in items)
              SizedBox(
                width: width,
                child: Panel(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 15, color: color == AppColors.text ? AppColors.muted : color),
                          const SizedBox(width: 6),
                          Flexible(child: Text(label, style: uStyle(12.5, weight: FontWeight.w700, color: AppColors.muted))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(value, style: uStyle(24, weight: FontWeight.w800, color: color)),
                      Text(hint, style: uStyle(11.5, color: AppColors.dim)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onOpenTab, required this.onChanged});

  final ValueChanged<int> onOpenTab;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.read(context).api;
    final actions = [
      (
        LucideIcons.bellRing,
        'Remind expired',
        () async {
          final ok = await confirmDialog(
            context,
            title: 'Remind users?',
            message: 'Sends a renewal reminder to users whose package has ended or ends within 3 days.',
            confirmLabel: 'Send reminders',
          );
          if (!ok || !context.mounted) return;
          await runAction(context, () async {
            final r = await api.remindExpired();
            if (context.mounted) {
              toast(context, 'Reminded ${r.expired.delivered + r.expiring.delivered} of ${r.expired.recipients + r.expiring.recipients} users');
            }
          });
        },
      ),
      (
        LucideIcons.send,
        'Notify users',
        () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const NotificationsScreen())),
      ),
      (
        LucideIcons.rotateCw,
        'Refresh apps',
        () async {
          final ok = await confirmDialog(
            context,
            title: 'Refresh all apps?',
            message: 'Every open AyomaMax app restarts and reloads channels, prices and settings.',
            confirmLabel: 'Refresh',
          );
          if (!ok || !context.mounted) return;
          await runAction(context, api.refreshApps, success: 'Apps will refresh on their next sync');
        },
      ),
      (LucideIcons.plus, 'Add channel', () => onOpenTab(1)),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.95,
      children: [
        for (final (icon, label, onTap) in actions)
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: AppColors.greenA(0.12), borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, size: 18, color: AppColors.ink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: uStyle(11.5, weight: FontWeight.w700, height: 1.2),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
