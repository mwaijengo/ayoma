import 'dart:async';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'payments_screen.dart';

Color userStatusColor(UserStatus s) => switch (s) {
  UserStatus.premium => AppColors.green,
  UserStatus.expired => AppColors.error,
  UserStatus.blocked => AppColors.red,
  UserStatus.free => AppColors.muted,
};

class UserAvatar extends StatelessWidget {
  const UserAvatar(this.user, {super.key, this.size = 40});

  final AppUser user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = userStatusColor(user.status);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(
        user.status == UserStatus.premium
            ? LucideIcons.crown
            : user.blocked
            ? LucideIcons.ban
            : LucideIcons.smartphone,
        size: size * 0.45,
        color: AppColors.ink,
      ),
    );
  }
}

/// Search sheet that returns the chosen user.
Future<AppUser?> pickUser(BuildContext context, {required String title}) {
  return showFormSheet<AppUser>(context, title: title, child: const _UserPicker());
}

class _UserPicker extends StatefulWidget {
  const _UserPicker();

  @override
  State<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<_UserPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<AppUser>? _users;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final page = await SessionScope.read(context).api.users(search: _search.text.trim());
      if (mounted) {
        setState(() {
          _users = page.users;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: TextField(
            controller: _search,
            autofocus: true,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _load);
            },
            decoration: const InputDecoration(
              hintText: 'Device ID, name or phone',
              prefixIcon: Icon(LucideIcons.search, size: 18),
            ),
          ),
        ),
        Flexible(
          child: users == null
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: _error != null
                      ? Text(_error!, style: uStyle(13, color: AppColors.error))
                      : const CircularProgressIndicator(strokeWidth: 2.4),
                )
              : users.isEmpty
              ? const EmptyState(icon: LucideIcons.userSearch, title: 'No users found')
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  children: [
                    for (final u in users)
                      ListTile(
                        onTap: () => Navigator.pop(context, u),
                        leading: UserAvatar(u, size: 36),
                        title: Text(u.displayName, style: uStyle(14, weight: FontWeight.w700)),
                        subtitle: Text(
                          '${u.deviceId} • ${u.status.label}',
                          style: uStyle(12, color: AppColors.muted),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Plan dropdown used by the grant and manual payment sheets.
class _PlanPicker extends StatelessWidget {
  const _PlanPicker({required this.plans, required this.value, required this.onChanged});

  final List<Plan> plans;
  final Plan? value;
  final ValueChanged<Plan?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Plan>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: AppColors.surface2,
      decoration: const InputDecoration(labelText: 'Package', prefixIcon: Icon(LucideIcons.package, size: 18)),
      items: [
        for (final p in plans)
          DropdownMenuItem(
            value: p,
            child: Text('${p.name} • ${p.days} days • ${formatTzs(p.priceTzs)}${p.active ? '' : ' (hidden)'}'),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

Future<bool?> showGrantSheet(BuildContext context, AppUser user) {
  return showFormSheet<bool>(context, title: 'Grant package', child: _GrantForm(user: user, manual: false));
}

Future<bool?> showManualPaymentSheet(BuildContext context, AppUser user) {
  return showFormSheet<bool>(context, title: 'Record payment', child: _GrantForm(user: user, manual: true));
}

/// Grant (free) or record a manual payment (counts as revenue).
class _GrantForm extends StatefulWidget {
  const _GrantForm({required this.user, required this.manual});

  final AppUser user;
  final bool manual;

  @override
  State<_GrantForm> createState() => _GrantFormState();
}

class _GrantFormState extends State<_GrantForm> {
  List<Plan>? _plans;
  Plan? _plan;
  final _days = TextEditingController();
  final _amount = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _phone.text = widget.user.phone;
    SessionScope.read(context).api.plans().then((plans) {
      if (!mounted) return;
      setState(() {
        _plans = plans;
        if (plans.isNotEmpty) _select(plans.firstWhere((p) => p.active, orElse: () => plans.first));
      });
    }, onError: (Object e) => mounted ? toast(context, '$e', error: true) : null);
  }

  void _select(Plan? p) {
    _plan = p;
    if (p == null) return;
    _days.text = '${p.days}';
    _amount.text = '${p.priceTzs}';
  }

  @override
  void dispose() {
    for (final c in [_days, _amount, _phone, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final plan = _plan;
    if (plan == null) return;
    final api = SessionScope.read(context).api;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => widget.manual
          ? api.manualPayment(
              userId: widget.user.id,
              planId: plan.id,
              amountTzs: int.tryParse(_amount.text.replaceAll(',', '')),
              phone: _phone.text.trim(),
              note: _note.text.trim(),
            )
          : api.grant(
              widget.user.id,
              planId: plan.id,
              days: int.tryParse(_days.text),
              note: _note.text.trim(),
            ),
      success: widget.manual ? 'Payment recorded and package activated' : 'Package granted',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    if (plans == null) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(
          widget.manual
              ? 'For money received outside the app (cash, direct transfer). It counts in revenue.'
              : 'Free access for ${widget.user.displayName}. It does not count in revenue. '
                    'Days are added on top of any time left.',
          style: uStyle(13, color: AppColors.muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        _PlanPicker(plans: plans, value: _plan, onChanged: (p) => setState(() => _select(p))),
        const SizedBox(height: 12),
        if (widget.manual) ...[
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount received (TSh)', prefixIcon: Icon(LucideIcons.banknote, size: 18)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)', prefixIcon: Icon(LucideIcons.phone, size: 18)),
          ),
        ] else
          TextField(
            controller: _days,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Days',
              helperText: 'Defaults to the package length; change it for custom access.',
              prefixIcon: Icon(LucideIcons.calendarDays, size: 18),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'Note (optional)', prefixIcon: Icon(LucideIcons.stickyNote, size: 18)),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy || _plan == null ? null : _save,
          child: Text(widget.manual ? 'Record payment' : 'Grant package'),
        ),
      ],
    );
  }
}

Future<bool?> showNotifyUserSheet(BuildContext context, AppUser user) {
  return showFormSheet<bool>(context, title: 'Notify ${user.displayName}', child: _NotifyUserForm(user: user));
}

class _NotifyUserForm extends StatefulWidget {
  const _NotifyUserForm({required this.user});

  final AppUser user;

  @override
  State<_NotifyUserForm> createState() => _NotifyUserFormState();
}

class _NotifyUserFormState extends State<_NotifyUserForm> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final api = SessionScope.read(context).api;
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      final r = await api.sendNotification(
        title: _title.text.trim(),
        body: _body.text.trim(),
        target: 'user',
        userId: widget.user.id,
      );
      if (r.delivered == 0) throw Exception('Not delivered. The app may be uninstalled or push is not set up.');
    }, success: 'Notification sent');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        if (!widget.user.hasPush)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'This device has not registered for push notifications yet.',
              style: uStyle(13, color: AppColors.amber),
            ),
          ),
        TextField(
          controller: _title,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _body, maxLines: 3, decoration: const InputDecoration(labelText: 'Message')),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy || _title.text.trim().isEmpty ? null : _send,
          icon: const Icon(LucideIcons.send, size: 16),
          label: const Text('Send'),
        ),
      ],
    );
  }
}

/// Full user detail with every admin action; [onChanged] runs after each change.
Future<void> showUserSheet(BuildContext context, int userId, {required VoidCallback onChanged}) {
  return showFormSheet<void>(context, title: 'User', child: _UserDetail(userId: userId, onChanged: onChanged));
}

class _UserDetail extends StatefulWidget {
  const _UserDetail({required this.userId, required this.onChanged});

  final int userId;
  final VoidCallback onChanged;

  @override
  State<_UserDetail> createState() => _UserDetailState();
}

class _UserDetailState extends State<_UserDetail> {
  AppUser? _user;
  List<Payment> _payments = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await SessionScope.read(context).api.user(widget.userId);
      if (mounted) {
        setState(() {
          _user = r.user;
          _payments = r.payments;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _after(Future<bool?> Function() action) async {
    final changed = await action();
    if (changed == true) {
      widget.onChanged();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: _error != null
              ? Text(_error!, style: uStyle(13, color: AppColors.error))
              : const CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    final api = SessionScope.read(context).api;
    final subscribed = user.expiresAt != null;
    return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Row(
            children: [
              UserAvatar(user, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName, style: uStyle(18, weight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(user.status.label.toUpperCase(), color: userStatusColor(user.status)),
                        if (user.hasPush) const Pill('PUSH', color: AppColors.blue, icon: LucideIcons.bell),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Panel(
            child: Column(
              children: [
                InfoRow('Device ID', user.deviceId, copy: true),
                InfoRow('Package', user.planName ?? '—'),
                InfoRow(
                  'Expires',
                  user.expiresAt == null ? '—' : '${formatDate(user.expiresAt)}\n${timeLeft(user.expiresAt)}',
                ),
                if (user.phone.isNotEmpty) InfoRow('Phone', user.phone, copy: true),
                InfoRow('App', '${user.platform.isEmpty ? '—' : user.platform} ${user.appVersion}'),
                InfoRow('Last seen', timeAgo(user.lastSeenAt)),
                InfoRow('Joined', formatDate(user.createdAt)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ActionButton(
                icon: LucideIcons.gift,
                label: subscribed ? 'Add days' : 'Grant package',
                primary: true,
                onTap: () => _after(() => showGrantSheet(context, user)),
              ),
              _ActionButton(
                icon: LucideIcons.banknote,
                label: 'Record payment',
                onTap: () => _after(() => showManualPaymentSheet(context, user)),
              ),
              _ActionButton(
                icon: LucideIcons.send,
                label: 'Notify',
                onTap: () => showNotifyUserSheet(context, user),
              ),
              if (subscribed)
                _ActionButton(
                  icon: LucideIcons.circleMinus,
                  label: 'Remove package',
                  danger: true,
                  onTap: () => _after(() async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Remove package?',
                      message: '${user.displayName} goes back to free immediately. Payment history is kept.',
                      confirmLabel: 'Remove',
                      destructive: true,
                    );
                    if (!ok || !context.mounted) return false;
                    return runAction(context, () => api.removeSubscription(user.id), success: 'Package removed');
                  }),
                ),
              _ActionButton(
                icon: user.blocked ? LucideIcons.lockOpen : LucideIcons.ban,
                label: user.blocked ? 'Unblock' : 'Block',
                danger: !user.blocked,
                onTap: () => _after(() async {
                  if (!user.blocked) {
                    final ok = await confirmDialog(
                      context,
                      title: 'Block this user?',
                      message: 'They cannot watch or pay until unblocked.',
                      confirmLabel: 'Block',
                      destructive: true,
                    );
                    if (!ok || !context.mounted) return false;
                  }
                  return runAction(
                    context,
                    () => api.setBlocked(user.id, !user.blocked),
                    success: user.blocked ? 'User unblocked' : 'User blocked',
                  );
                }),
              ),
              _ActionButton(
                icon: LucideIcons.trash2,
                label: 'Delete',
                danger: true,
                onTap: () async {
                  final ok = await confirmDialog(
                    context,
                    title: 'Delete user?',
                    message: 'Removes the device and all its payment records. The app registers again as a new free user.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                  if (!ok || !context.mounted) return;
                  final done = await runAction(context, () => api.deleteUser(user.id), success: 'User deleted');
                  if (!done) return;
                  widget.onChanged();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
          const SectionLabel('Payments'),
          if (_payments.isEmpty)
            Text('No payments yet', style: uStyle(13, color: AppColors.muted))
          else
            Panel(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final p in _payments)
                    PaymentTile(
                      payment: p,
                      onChanged: () async {
                        widget.onChanged();
                        await _load();
                      },
                    ),
                ],
              ),
            ),
        ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = primary || danger ? AppColors.ink : AppColors.text;
    return Material(
      color: primary ? AppColors.green : (danger ? AppColors.red : AppColors.surface2),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(label, style: uStyle(13, weight: FontWeight.w700, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
