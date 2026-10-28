import 'dart:async';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/admin_api.dart';
import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'user_sheets.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final _listKey = GlobalKey<AsyncListState<PaymentPage>>();
  final _search = TextEditingController();
  Timer? _debounce;
  String _status = 'all';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _reload() => _listKey.currentState?.reload();

  Future<void> _recordPayment() async {
    final user = await pickUser(context, title: 'Record payment for…');
    if (user == null || !mounted) return;
    final saved = await showManualPaymentSheet(context, user);
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.read(context).api;
    return Column(
      children: [
        PageHeader(
          title: 'Payments',
          subtitle: 'SonicPesa and manual payments',
          actions: [
            FilledButton.icon(
              onPressed: _recordPayment,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Record'),
            ),
            const SizedBox(width: 6),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), _reload);
            },
            decoration: const InputDecoration(
              hintText: 'Search phone, order ID, device ID or name',
              prefixIcon: Icon(LucideIcons.search, size: 18),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final s in const ['all', 'paid', 'pending', 'failed'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s[0].toUpperCase() + s.substring(1)),
                    selected: _status == s,
                    onSelected: (_) {
                      setState(() => _status = s);
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncList<PaymentPage>(
            key: _listKey,
            load: () => api.payments(status: _status, search: _search.text.trim()),
            builder: (context, page, reload) => [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                child: Text(
                  '${page.total} payment${page.total == 1 ? '' : 's'}  •  ${formatTzs(page.totalPaidTzs)} received',
                  style: uStyle(13, color: AppColors.muted),
                ),
              ),
              if (page.payments.isEmpty)
                const EmptyState(icon: LucideIcons.wallet, title: 'No payments found')
              else
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [for (final p in page.payments) PaymentTile(payment: p, onChanged: reload)],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class PaymentTile extends StatelessWidget {
  const PaymentTile({super.key, required this.payment, required this.onChanged});

  final Payment payment;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final color = paymentStatusColor(p.status);
    return ListTile(
      onTap: () async {
        final changed = await showPaymentSheet(context, p);
        if (changed == true) await onChanged();
      },
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(
          switch (p.status) {
            'paid' => LucideIcons.check,
            'pending' => LucideIcons.hourglass,
            _ => LucideIcons.x,
          },
          size: 18,
          color: color,
        ),
      ),
      title: Text(p.who, maxLines: 1, overflow: TextOverflow.ellipsis, style: uStyle(14.5, weight: FontWeight.w700)),
      subtitle: Text(
        '${p.planName} • ${p.providerLabel} • ${timeAgo(p.createdAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: uStyle(12, color: AppColors.muted),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            p.provider == 'admin_grant' ? 'Free' : formatTzs(p.amountTzs),
            style: uStyle(14, weight: FontWeight.w800, color: p.status == 'paid' ? AppColors.text : AppColors.muted),
          ),
          const SizedBox(height: 3),
          Pill(p.status.toUpperCase(), color: color),
        ],
      ),
    );
  }
}

Future<bool?> showPaymentSheet(BuildContext context, Payment p) {
  final api = SessionScope.read(context).api;
  return showFormSheet<bool>(
    context,
    title: 'Payment #${p.id}',
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Panel(
          child: Column(
            children: [
              InfoRow('Status', p.status.toUpperCase(), color: paymentStatusColor(p.status)),
              InfoRow('Amount', p.provider == 'admin_grant' ? 'Free grant' : formatTzs(p.amountTzs)),
              InfoRow('Package', '${p.planName} (${p.days} days)'),
              InfoRow('Method', p.providerLabel),
              InfoRow('User', p.who),
              if (p.deviceId != null) InfoRow('Device ID', p.deviceId!, copy: true),
              if (p.phone.isNotEmpty) InfoRow('Phone', p.phone, copy: true),
              if (p.orderId.isNotEmpty) InfoRow('Order ID', p.orderId, copy: true),
              InfoRow('Created', formatDate(p.createdAt)),
              if (p.paidAt != null) InfoRow('Paid', formatDate(p.paidAt)),
              if (p.message.isNotEmpty) InfoRow('Message', p.message),
              if (p.note.isNotEmpty) InfoRow('Note', p.note),
            ],
          ),
        ),
        if (p.status != 'paid') ...[
          const SizedBox(height: 16),
          Builder(
            builder: (context) => FilledButton.icon(
              icon: const Icon(LucideIcons.badgeCheck, size: 18),
              label: const Text('Confirm as paid'),
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Confirm payment?',
                  message:
                      'Only confirm after checking the money arrived in SonicPesa. The user gets ${p.days} days of ${p.planName}.',
                  confirmLabel: 'Confirm paid',
                );
                if (!ok || !context.mounted) return;
                final done = await runAction(context, () => api.confirmPayment(p.id), success: 'Payment confirmed');
                if (done && context.mounted) Navigator.pop(context, true);
              },
            ),
          ),
        ],
      ],
    ),
  );
}