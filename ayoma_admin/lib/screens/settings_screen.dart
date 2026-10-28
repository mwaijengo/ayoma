import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

final _version = RegExp(r'^\d+(\.\d+){0,2}$');

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.scrollToDanger = false});

  final bool scrollToDanger;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _dangerKey = GlobalKey();
  AppSettings? _settings;
  String? _error;

  final _maintenanceMsg = TextEditingController();
  final _latest = TextEditingController();
  final _min = TextEditingController();
  final _updateMsg = TextEditingController();
  final _updateUrl = TextEditingController();
  final _whatsapp = TextEditingController();
  bool _maintenance = false;
  bool _force = false;
  String? _savingSection;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_maintenanceMsg, _latest, _min, _updateMsg, _updateUrl, _whatsapp]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await SessionScope.read(context).api.settings();
      if (!mounted) return;
      _apply(s);
      if (widget.scrollToDanger) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _dangerKey.currentContext;
          if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400));
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _apply(AppSettings s) {
    setState(() {
      _settings = s;
      _error = null;
      _maintenance = s.maintenanceEnabled;
      _maintenanceMsg.text = s.maintenanceMessage;
      _latest.text = s.latestVersion;
      _min.text = s.minVersion;
      _force = s.forceUpdate;
      _updateMsg.text = s.updateMessage;
      _updateUrl.text = s.updateUrl;
      _whatsapp.text = s.supportWhatsApp;
    });
  }

  Future<void> _save(String section, Json patch, String success) async {
    final api = SessionScope.read(context).api;
    setState(() => _savingSection = section);
    await runAction(context, () async {
      final s = await api.updateSettings(patch);
      if (mounted) _apply(s);
    }, success: success);
    if (mounted) setState(() => _savingSection = null);
  }

  Future<void> _saveMaintenance(bool enabled) async {
    if (enabled) {
      final ok = await confirmDialog(
        context,
        title: 'Turn on maintenance?',
        message: 'Every user sees the maintenance screen and cannot watch until you turn it off.',
        confirmLabel: 'Turn on',
        destructive: true,
      );
      if (!ok) return;
    }
    await _save(
      'maintenance',
      {
        'maintenance': {'enabled': enabled, 'message': _maintenanceMsg.text.trim()},
      },
      enabled ? 'Maintenance mode is ON' : 'Maintenance mode is OFF',
    );
  }

  Future<void> _saveUpdate() async {
    final latest = _latest.text.trim();
    final min = _min.text.trim();
    if (!_version.hasMatch(latest) || !_version.hasMatch(min)) {
      toast(context, 'Versions must look like 1.2.0', error: true);
      return;
    }
    if (_force) {
      final ok = await confirmDialog(
        context,
        title: 'Force update?',
        message: 'Users on versions older than $min must update before they can use the app.',
        confirmLabel: 'Save',
      );
      if (!ok) return;
    }
    await _save(
      'update',
      {
        'appUpdate': {
          'latestVersion': latest,
          'minVersion': min,
          'force': _force,
          'message': _updateMsg.text.trim(),
          'url': _updateUrl.text.trim(),
        },
      },
      'Update settings saved',
    );
  }

  Future<void> _refreshApps() async {
    final ok = await confirmDialog(
      context,
      title: 'Refresh all apps?',
      message: 'Every open AyomaMax app restarts and reloads channels, prices and settings.',
      confirmLabel: 'Refresh',
    );
    if (!ok || !mounted) return;
    final api = SessionScope.read(context).api;
    await runAction(context, () async {
      final pushed = await api.refreshApps();
      if (mounted) {
        toast(context, pushed ? 'Refresh sent to all devices' : 'Apps refresh on their next sync (within a minute)');
      }
    });
  }

  Future<void> _downgradeAll() async {
    final ok = await confirmDialog(
      context,
      title: 'Downgrade ALL premium users?',
      message:
          'Every active package ends now and all users become free. Payment history is kept, but '
          'this cannot be undone; you would have to grant packages again one by one.',
      confirmLabel: 'Downgrade everyone',
      destructive: true,
      typeToConfirm: 'DOWNGRADE',
    );
    if (!ok || !mounted) return;
    final api = SessionScope.read(context).api;
    await runAction(context, () async {
      final count = await api.downgradeAll();
      if (mounted) toast(context, '$count user${count == 1 ? '' : 's'} downgraded to free');
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('App settings', style: uStyle(18, weight: FontWeight.w800)),
      ),
      body: s == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator(strokeWidth: 2.4)
                  : EmptyState(
                      icon: LucideIcons.wifiOff,
                      title: 'Could not load settings',
                      message: _error,
                      action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              children: [
                const SectionLabel('Maintenance mode'),
                Panel(
                  borderColor: _maintenance ? AppColors.amber.withValues(alpha: 0.5) : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchRow(
                        title: _maintenance ? 'Maintenance is ON' : 'Maintenance is off',
                        subtitle: 'Zuia app muda wa matengenezo, mtumiaji hawezi kutUMIA app',
                        value: _maintenance,
                        onChanged: _savingSection != null ? null : _saveMaintenance,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _maintenanceMsg,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Message shown to users',
                          hintText: 'Tunafanya maboresho. Tutarudi hivi punde.',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _savingSection != null ? null : () => _saveMaintenance(_maintenance),
                          child: const Text('Save message'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionLabel('App update'),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _latest,
                              decoration: const InputDecoration(labelText: 'Latest version', hintText: '1.2.0'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _min,
                              decoration: const InputDecoration(labelText: 'Minimum version', hintText: '1.0.0'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchRow(
                        title: 'Must update',
                        subtitle: 'Older than the minimum version: app is blocked until updated. '
                            'Otherwise users hawatoweza kutumia app.',
                        value: _force,
                        onChanged: (v) => setState(() => _force = v),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _updateMsg,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Update message',
                          hintText: 'Kuna toleo jipya. Download sasa upate maboresho.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _updateUrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Download link',
                          hintText: 'https://play.google.com/store/apps/details?id=…',
                          prefixIcon: Icon(LucideIcons.download, size: 18),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: _savingSection != null ? null : _saveUpdate,
                        child: const Text('Save update settings'),
                      ),
                    ],
                  ),
                ),
                const SectionLabel('Support'),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _whatsapp,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'WhatsApp number',
                          hintText: '255712345678',
                          helperText: 'Format 255XXXXXXXXX. Used by "Wasiliana nasi" in the app.',
                          prefixIcon: Icon(LucideIcons.messageCircle, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _savingSection != null
                            ? null
                            : () => _save('support', {'supportWhatsApp': _whatsapp.text.trim()}, 'WhatsApp number saved'),
                        child: const Text('Save number'),
                      ),
                    ],
                  ),
                ),
                const SectionLabel('Refresh'),
                Panel(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Restart every user app so it loads the latest channels, prices and settings right away.',
                          style: uStyle(13, color: AppColors.muted, height: 1.4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _refreshApps,
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                        icon: const Icon(LucideIcons.rotateCw, size: 16),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                ),
                const SectionLabel('Server services'),
                Panel(
                  child: Column(
                    children: [
                      _ServiceRow('SonicPesa payments', s.services['sonicPesa'] == true),
                      _ServiceRow('SonicPesa webhook signature', s.services['sonicPesaWebhook'] == true),
                      _ServiceRow('Push notifications (FCM)', s.services['push'] == true),
                    ],
                  ),
                ),
                SectionLabel('Danger zone', key: _dangerKey),
                Panel(
                  color: AppColors.red.withValues(alpha: 0.06),
                  borderColor: AppColors.red.withValues(alpha: 0.35),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.triangleAlert, size: 18, color: AppColors.error),
                          const SizedBox(width: 8),
                          Text('Downgrade all premium users', style: uStyle(15, weight: FontWeight.w800, color: AppColors.error)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Chomoa betri kwa watumiaji wote '
                        'watumiaji wote wataondolewa premium.',
                        style: uStyle(13, color: AppColors.muted, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
                        onPressed: _downgradeAll,
                        icon: const Icon(LucideIcons.userX, size: 18),
                        label: const Text('Downgrade everyone to free'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow(this.label, this.ok);

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(ok ? LucideIcons.circleCheck : LucideIcons.circleDashed, size: 17, color: ok ? AppColors.green : AppColors.dim),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: uStyle(13.5, weight: FontWeight.w600))),
          Text(ok ? 'Configured' : 'Not set', style: uStyle(12, color: ok ? AppColors.green : AppColors.dim)),
        ],
      ),
    );
  }
}
