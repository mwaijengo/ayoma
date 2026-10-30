import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../theme.dart';

String formatTzs(int amount) {
  final digits = amount.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}TSh $buf';
}

String _two(int n) => n.toString().padLeft(2, '0');

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatDate(DateTime? d, {bool time = true}) {
  if (d == null) return '—';
  final date = '${d.day} ${_months[d.month - 1]} ${d.year}';
  return time ? '$date, ${_two(d.hour)}:${_two(d.minute)}' : date;
}

String timeAgo(DateTime? d) {
  if (d == null) return 'never';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return formatDate(d, time: false);
}

String timeLeft(DateTime? d) {
  if (d == null) return 'No package';
  final diff = d.difference(DateTime.now());
  if (diff.isNegative) return 'Ended ${timeAgo(d)}';
  if (diff.inDays >= 1) return '${diff.inDays}d ${diff.inHours % 24}h left';
  if (diff.inHours >= 1) return '${diff.inHours}h ${diff.inMinutes % 60}m left';
  return '${diff.inMinutes}m left';
}

void toast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            error ? LucideIcons.circleAlert : LucideIcons.circleCheck,
            size: 18,
            color: error ? AppColors.error : AppColors.green,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

/// Runs [action], shows its error as a toast and returns whether it succeeded.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) toast(context, success);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, e is ApiException ? e.message : '$e', error: true);
    return false;
  }
}

/// Confirmation dialog. When [typeToConfirm] is set the user must type it exactly.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
  String? typeToConfirm,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final ready = typeToConfirm == null || controller.text.trim() == typeToConfirm;
        return AlertDialog(
          title: Text(title, style: uStyle(18, weight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: uStyle(14, color: AppColors.muted, height: 1.45)),
              if (typeToConfirm != null) ...[
                const SizedBox(height: 16),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Type '),
                      TextSpan(
                        text: typeToConfirm,
                        style: uStyle(13, weight: FontWeight.w800, color: AppColors.error),
                      ),
                      const TextSpan(text: ' to confirm'),
                    ],
                  ),
                  style: uStyle(13, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 42),
                    )
                  : FilledButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: ready ? () => Navigator.pop(context, true) : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
  return result ?? false;
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.borderColor});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: borderColor ?? AppColors.line),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: uStyle(11.5, weight: FontWeight.w800, color: AppColors.dim, letterSpacing: 1.2),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color = AppColors.muted, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: AppColors.ink), const SizedBox(width: 4)],
          Text(label, style: uStyle(10.5, weight: FontWeight.w800, color: AppColors.ink, letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

Color paymentStatusColor(String status) => switch (status) {
  'paid' => AppColors.green,
  'pending' => AppColors.amber,
  _ => AppColors.error,
};

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(18)),
            child: Icon(icon, color: AppColors.dim),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: uStyle(16, weight: FontWeight.w800)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: uStyle(13, color: AppColors.muted, height: 1.4)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Loads data with [load], shows loading / error / content and supports pull-to-refresh.
class AsyncList<T> extends StatefulWidget {
  const AsyncList({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final List<Widget> Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<AsyncList<T>> createState() => AsyncListState<T>();
}

class AsyncListState<T> extends State<AsyncList<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() => _loading = true);
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final List<Widget> children;
    if (data == null && _loading) {
      children = const [
        SizedBox(height: 160),
        Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      ];
    } else if (data == null) {
      children = [
        EmptyState(
          icon: LucideIcons.wifiOff,
          title: 'Could not load',
          message: _error is ApiException ? (_error as ApiException).message : '$_error',
          action: OutlinedButton.icon(
            onPressed: reload,
            icon: const Icon(LucideIcons.rotateCw, size: 16),
            label: const Text('Try again'),
          ),
        ),
      ];
    } else {
      children = widget.builder(context, data, reload);
    }
    return RefreshIndicator(
      color: AppColors.green,
      backgroundColor: AppColors.surface2,
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (_loading && data != null) const LinearProgressIndicator(minHeight: 2),
          ...children,
        ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: uStyle(24, weight: FontWeight.w800, letterSpacing: -0.4)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: uStyle(13, color: AppColors.muted)),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Bottom sheet scaffold with a title and scrollable form body.
Future<T?> showFormSheet<T>(BuildContext context, {required String title, required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: uStyle(19, weight: FontWeight.w800))),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    ),
  );
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: uStyle(14.5, weight: FontWeight.w700)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: uStyle(12.5, color: AppColors.muted, height: 1.35)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.color, this.copy = false});

  final String label;
  final String value;
  final Color? color;
  final bool copy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(label, style: uStyle(13, color: AppColors.dim))),
          Expanded(
            child: Text(value, style: uStyle(13.5, weight: FontWeight.w700, color: color ?? AppColors.text)),
          ),
          if (copy)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                toast(context, '$label copied');
              },
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(LucideIcons.copy, size: 15, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.width, this.height, this.radius = 12});

  final String url;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: AppColors.surface2,
      child: const Icon(LucideIcons.image, size: 18, color: AppColors.faint),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
