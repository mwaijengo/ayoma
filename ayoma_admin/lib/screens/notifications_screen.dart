import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'user_sheets.dart';

const _targets = [
  ('all', 'Everyone', LucideIcons.users),
  ('premium', 'Premium', LucideIcons.crown),
  ('free', 'Free users', LucideIcons.user),
  ('expiring', 'Expiring (3 days)', LucideIcons.clock3),
  ('expired', 'Expired', LucideIcons.userX),
  ('user', 'One user', LucideIcons.userSearch),
];

String _targetLabel(String target) {
  if (target.startsWith('user:')) return 'User #${target.substring(5)}';
  if (target == 'auto:expiring') return 'Auto reminder • Ending soon';
  if (target == 'auto:expired') return 'Auto reminder • Expired';
  return _targets.where((t) => t.$1 == target).firstOrNull?.$2 ?? target;
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _listKey = GlobalKey<AsyncListState<({bool pushConfigured, List<NotificationLog> items})>>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _target = 'all';
  AppUser? _user;
  bool _busy = false;
  final _resending = <int>{};

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _canSend => !_busy && _title.text.trim().isNotEmpty && (_target != 'user' || _user != null);

  Future<void> _send() async {
    final label = _target == 'user' ? _user!.displayName : _targetLabel(_target);
    final ok = await confirmDialog(
      context,
      title: 'Send notification?',
      message: '"${_title.text.trim()}" will be sent to: $label.',
      confirmLabel: 'Send',
    );
    if (!ok || !mounted) return;
    final api = SessionScope.read(context).api;
    setState(() => _busy = true);
    final sent = await runAction(context, () async {
      final r = await api.sendNotification(
        title: _title.text.trim(),
        body: _body.text.trim(),
        target: _target,
        userId: _target == 'user' ? _user!.id : null,
      );
      if (mounted) toast(context, 'Delivered to ${r.delivered} of ${r.recipients} devices');
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (sent) {
      _title.clear();
      _body.clear();
      _listKey.currentState?.reload();
    }
  }

  Future<void> _remind() async {
    final ok = await confirmDialog(
      context,
      title: 'Remind users?',
      message: 'Sends "Kifurushi chako kimeisha" to expired users and "kinakaribia kuisha" to users with under 3 days left.',
      confirmLabel: 'Send reminders',
    );
    if (!ok || !mounted) return;
    final api = SessionScope.read(context).api;
    await runAction(context, () async {
      final r = await api.remindExpired();
      if (mounted) {
        toast(context, 'Expired: ${r.expired.delivered}/${r.expired.recipients} • Expiring: ${r.expiring.delivered}/${r.expiring.recipients}');
      }
    });
    _listKey.currentState?.reload();
  }

  Future<void> _resend(NotificationLog n) async {
    final ok = await confirmDialog(
      context,
      title: 'Resend notification?',
      message: '"${n.title}" will be sent again to: ${_targetLabel(n.target)}.',
      confirmLabel: 'Resend',
    );
    if (!ok || !mounted) return;
    final api = SessionScope.read(context).api;
    setState(() => _resending.add(n.id));
    await runAction(context, () async {
      final r = await api.resendNotification(n.id);
      if (mounted) toast(context, 'Delivered to ${r.delivered} of ${r.recipients} devices');
    });
    if (!mounted) return;
    setState(() => _resending.remove(n.id));
    _listKey.currentState?.reload();
  }

  Future<void> _clearAll() async {
    final ok = await confirmDialog(
      context,
      title: 'Clear all notifications?',
      message: 'This deletes the whole sent history. Messages already on users\' phones are not affected.',
      confirmLabel: 'Clear all',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = SessionScope.read(context).api;
    await runAction(context, api.clearNotifications, success: 'History cleared');
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.read(context).api;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('Notifications', style: uStyle(18, weight: FontWeight.w800)),
      ),
      body: AsyncList<({bool pushConfigured, List<NotificationLog> items})>(
        key: _listKey,
        load: api.notifications,
        builder: (context, data, reload) => [
          if (!data.pushConfigured)
            Panel(
              color: AppColors.amber.withValues(alpha: 0.08),
              borderColor: AppColors.amber.withValues(alpha: 0.3),
              child: Row(
                children: [
                  const Icon(LucideIcons.triangleAlert, size: 18, color: AppColors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Push is not configured on the server (FCM_SERVICE_ACCOUNT_JSON). Messages are logged but not delivered.',
                      style: uStyle(12.5, color: AppColors.amber, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          const SectionLabel('Renewal reminder'),
          Panel(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Remind all expired users and users whose package ends within 3 days. '
                    'Each user is also reminded automatically a day before and right after their package ends.',
                    style: uStyle(13, color: AppColors.muted, height: 1.4),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _remind,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                  icon: const Icon(LucideIcons.bellRing, size: 16),
                  label: const Text('Remind'),
                ),
              ],
            ),
          ),
          const SectionLabel('New message'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (id, label, icon) in _targets)
                      ChoiceChip(
                        avatar: Icon(icon, size: 14),
                        label: Text(label),
                        selected: _target == id,
                        onSelected: (_) async {
                          if (id == 'user') {
                            final user = await pickUser(context, title: 'Send to…');
                            if (user == null) return;
                            setState(() {
                              _target = id;
                              _user = user;
                            });
                          } else {
                            setState(() => _target = id);
                          }
                        },
                      ),
                  ],
                ),
                if (_target == 'user' && _user != null) ...[
                  const SizedBox(height: 10),
                  Text('To: ${_user!.displayName} (${_user!.deviceId})', style: uStyle(13, color: AppColors.green)),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _title,
                  maxLength: 100,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Title', hintText: 'Mechi ya leo: Simba vs Yanga'),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _body,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Message', hintText: 'Tazama mubashara saa 1 usiku.'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _canSend ? _send : null,
                  icon: const Icon(LucideIcons.send, size: 16),
                  label: const Text('Send notification'),
                ),
              ],
            ),
          ),
          SectionLabel(
            'History',
            trailing: data.items.isEmpty
                ? null
                : TextButton.icon(
                    onPressed: _clearAll,
                    style: TextButton.styleFrom(foregroundColor: AppColors.red),
                    icon: const Icon(LucideIcons.trash2, size: 15),
                    label: const Text('Clear all'),
                  ),
          ),
          if (data.items.isEmpty)
            Text('Nothing sent yet', style: uStyle(13, color: AppColors.muted))
          else
            Panel(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final n in data.items)
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 16, right: 6),
                      title: Text(n.title, style: uStyle(14, weight: FontWeight.w700)),
                      subtitle: Text(
                        '${_targetLabel(n.target)} • ${timeAgo(n.createdAt)}${n.body.isEmpty ? '' : '\n${n.body}'}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: uStyle(12, color: AppColors.muted, height: 1.35),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${n.delivered}/${n.recipients}',
                            style: uStyle(13, weight: FontWeight.w800, color: n.delivered > 0 ? AppColors.green : AppColors.dim),
                          ),
                          _resending.contains(n.id)
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : IconButton(
                                  tooltip: 'Resend',
                                  onPressed: () => _resend(n),
                                  icon: const Icon(LucideIcons.rotateCw, size: 18, color: AppColors.green),
                                ),
                        ],
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
