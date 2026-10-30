import 'dart:async';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'app_restarter.dart';
import 'common.dart';

/// Applies what the admin set on the server: must-update, maintenance,
/// blocked devices, "refresh apps" and the optional update prompt.
class RemoteControl extends StatefulWidget {
  const RemoteControl({super.key, required this.child});

  final Widget child;

  @override
  State<RemoteControl> createState() => _RemoteControlState();
}

class _RemoteControlState extends State<RemoteControl> with WidgetsBindingObserver {
  /// Versions already offered this run, so the prompt shows once each.
  static final _prompted = <String>{};

  Timer? _promptDelay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promptDelay?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed) return;
    final state = AppScope.read(context);
    state.checkExpiry();
    state.sync();
  }

  void _afterBuild(AppState state) {
    if (state.restartRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !state.restartRequested) return;
        state.acknowledgeRestart();
        AppRestarter.restart(context);
      });
      return;
    }
    final version = state.config.latestVersion;
    if (state.updateAvailable && !state.updateRequired && !_prompted.contains(version)) {
      _prompted.add(version);
      // Waits for the splash to finish before asking.
      _promptDelay = Timer(const Duration(seconds: 4), () {
        if (mounted) _showUpdatePrompt(state);
      });
    }
  }

  Future<void> _showUpdatePrompt(AppState state) {
    final message = state.config.updateMessage;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.sheet,
        title: Text('Toleo jipya ${state.config.latestVersion}', style: uStyle(17, weight: FontWeight.w700)),
        content: Text(
          message.isEmpty ? 'Kuna toleo jipya la AyomaMax. Download sasa upate huduma bora.' : message,
          style: uStyle(12, color: AppColors.muted, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Baadaye', style: uStyle(12, color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openUpdate(state);
            },
            child: Text('Download sasa', style: uStyle(12, weight: FontWeight.w700, color: AppColors.green)),
          ),
        ],
      ),
    );
  }

  Future<void> _openUpdate(AppState state) async {
    final url = Uri.tryParse(state.config.updateUrl);
    var opened = false;
    if (url != null && url.hasScheme) {
      try {
        opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) showAppToast(context, 'Imeshindikana kufungua kiungo cha kudownload');
  }

  Future<void> _openWhatsApp(AppState state) async {
    final message = Uri.encodeComponent(
      'Habari AyomaMax, akaunti yangu imezuiwa.\nNamba ya kifaa: ${state.deviceId}',
    );
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse('https://wa.me/${state.config.supportWhatsApp}?text=$message'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) showAppToast(context, 'Imeshindikana kufungua WhatsApp');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    _afterBuild(state);

    if (state.updateRequired) {
      final message = state.config.updateMessage;
      return StatusScreen(
        icon: LucideIcons.download,
        title: 'Kuna toleo jipya',
        message: message.isEmpty
            ? 'Toleo hili halitumiki tena. Download toleo jipya ili uendelee kutazama.'
            : message,
        action: 'Download sasa',
        onAction: () => _openUpdate(state),
      );
    }
    if (state.config.maintenance) {
      final message = state.config.maintenanceMessage;
      return StatusScreen(
        icon: LucideIcons.wrench,
        title: 'Tunaboresha huduma',
        message: message.isEmpty
            ? 'AyomaMax iko kwenye matengenezo kwa muda mfupi. Tafadhali rudi baadaye.'
            : message,
        action: 'Jaribu tena',
        onAction: () => state.sync(force: true),
      );
    }
    if (state.blocked) {
      return StatusScreen(
        icon: LucideIcons.shieldBan,
        title: 'Akaunti imezuiwa',
        message: 'Kifaa hiki kimezuiwa kutumia AyomaMax. Wasiliana nasi kwa msaada.',
        action: 'Wasiliana nasi',
        onAction: () => _openWhatsApp(state),
        secondary: 'Jaribu tena',
        onSecondary: () => state.sync(force: true),
      );
    }
    return widget.child;
  }
}

/// Full-screen message used for maintenance, must-update and blocked states.
class StatusScreen extends StatefulWidget {
  const StatusScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
    this.secondary,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String action;
  final FutureOr<void> Function() onAction;
  final String? secondary;
  final FutureOr<void> Function()? onSecondary;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  bool _busy = false;

  Future<void> _run(FutureOr<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.greenA(0.1),
                    border: Border.all(color: AppColors.greenA(0.3)),
                  ),
                  child: Icon(widget.icon, size: 34, color: AppColors.ink),
                ),
                const SizedBox(height: 22),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: uStyle(21, weight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: uStyle(12, color: AppColors.muted, height: 1.7),
                  ),
                ),
                const SizedBox(height: 26),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: AppButton(
                    label: widget.action,
                    loading: _busy,
                    onTap: () => _run(widget.onAction),
                  ),
                ),
                if (widget.secondary != null) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _busy ? null : () => _run(widget.onSecondary!),
                    child: Text(widget.secondary!, style: uStyle(12, color: AppColors.muted)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
