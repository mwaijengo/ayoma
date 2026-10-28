import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_restarter.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.onSubscribe});

  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final plan = state.subscription;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Settings',
              style: uStyle(25, weight: FontWeight.w800, letterSpacing: -1),
            ),
            const SizedBox(height: 20),
            GlowCard(
              radius: 18,
              color: AppColors.surface,
              borderColor: AppColors.greenA(0.18),
              glowCenter: const Alignment(0.8, -0.8),
              glowRadius: 0.63,
              glowAlpha: 0.12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.crown,
                        size: 17,
                        color: AppColors.green,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          plan == null
                              ? 'KIFURUSHI CHA BURE'
                              : 'KIFURUSHI: ${plan.name.toUpperCase()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: uStyle(
                            10,
                            weight: FontWeight.w800,
                            color: AppColors.green,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        plan == null ? 'Unaweza kulipia' : 'Kinatumika',
                        style: uStyle(9, color: AppColors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (plan == null) ...[
                    Text(
                      'Siku 0 zimebaki',
                      style: uStyle(
                        24,
                        weight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const ProgressBar(
                      value: 0.03,
                      height: 4,
                      track: Color(0xFF2A312E),
                    ),
                  ] else
                    CountdownBuilder(
                      builder: (context, remaining, fraction) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CountdownUnits(remaining: remaining, compact: true),
                          const SizedBox(height: 12),
                          ProgressBar(
                            value: fraction,
                            height: 4,
                            track: const Color(0xFF2A312E),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 18),
                  AppButton(
                    label: plan == null ? 'Chagua kifurushi' : 'Ongeza muda',
                    onTap: onSubscribe,
                  ),
                ],
              ),
            ),
            const _SettingsLabel('SIMU HII'),
            _SettingsGroup(
              children: [
                _SettingRow(
                  icon: LucideIcons.smartphone,
                  title: 'Namba ya kifaa (ID)',
                  subtitle: state.deviceId,
                  trailing: _CopyButton(onTap: () => _copyId(context, state)),
                  onTap: () => _copyId(context, state),
                ),
              ],
            ),
            const _SettingsLabel('KICHEZAJI'),
            _SettingsGroup(
              children: [
                _SettingRow(
                  icon: LucideIcons.monitorPlay,
                  title: 'Ubora wa video',
                  subtitle: state.quality.label,
                  trailing: const Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: AppColors.muted,
                  ),
                  onTap: () => _pickQuality(context, state),
                ),
                _SettingRow(
                  icon: LucideIcons.volumeX,
                  title: 'Anza bila sauti',
                  subtitle: 'Chaneli ifunguke sauti ikiwa imezimwa',
                  trailing: UToggle(value: state.startMuted),
                  onTap: () => state.setStartMuted(!state.startMuted),
                ),
                _SettingRow(
                  icon: LucideIcons.rotateCw,
                  title: 'Cheza kwa mlalo',
                  subtitle: 'Video ifunguke skrini ikiwa imelala',
                  trailing: UToggle(value: state.autoLandscape),
                  onTap: () => state.setAutoLandscape(!state.autoLandscape),
                ),
                _SettingRow(
                  icon: LucideIcons.eyeOff,
                  title: 'Ficha vitufe',
                  subtitle: 'Vitufe vijifiche baada ya sekunde 4',
                  trailing: UToggle(value: state.autoHideControls),
                  onTap: () =>
                      state.setAutoHideControls(!state.autoHideControls),
                ),
              ],
            ),
            const _SettingsLabel('ARIFA NA BANDO'),
            _SettingsGroup(
              children: [
                _SettingRow(
                  icon: LucideIcons.bell,
                  title: 'Arifa za mechi',
                  subtitle: 'Pata taarifa kabla mechi haijaanza',
                  trailing: UToggle(value: state.notifications),
                  onTap: () => state.setNotifications(!state.notifications),
                ),
                _SettingRow(
                  icon: LucideIcons.wifi,
                  title: 'Okoa bando',
                  subtitle: 'Tumia bando kidogo',
                  trailing: UToggle(value: state.dataSaver),
                  onTap: () => state.setDataSaver(!state.dataSaver),
                ),
              ],
            ),
            const _SettingsLabel('HIFADHI'),
            _SettingsGroup(
              children: [
                _SettingRow(
                  icon: LucideIcons.trash2,
                  title: 'Futa akiba (cache)',
                  subtitle: 'Safisha programu na ianze upya',
                  trailing: const Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: AppColors.muted,
                  ),
                  onTap: () => _confirmClearCache(context),
                ),
              ],
            ),
            const _SettingsLabel('MSAADA'),
            _SettingsGroup(
              children: [
                _SettingRow(
                  icon: LucideIcons.messageCircle,
                  iconColor: _whatsAppGreen,
                  title: 'Msaada kwa WhatsApp',
                  subtitle: 'Ongea nasi moja kwa moja',
                  trailing: const Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: AppColors.muted,
                  ),
                  onTap: () => _openWhatsApp(context, state),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  static void _copyId(BuildContext context, AppState state) {
    Clipboard.setData(ClipboardData(text: state.deviceId));
    HapticFeedback.lightImpact();
    showAppToast(context, 'Namba ya kifaa imenakiliwa');
  }

  static Future<void> _openWhatsApp(
    BuildContext context,
    AppState state,
  ) async {
    final message = Uri.encodeComponent(
      'Habari AyomaMax, naomba msaada.\nNamba ya kifaa: ${state.deviceId}',
    );
    final uri = Uri.parse(
      'https://wa.me/${state.config.supportWhatsApp}?text=$message',
    );
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      showAppToast(context, 'Imeshindikana kufungua WhatsApp');
    }
  }

  static Future<void> _confirmClearCache(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xB3000000),
      builder: (_) => const _ClearCacheSheet(),
    );
  }

  static Future<void> _pickQuality(BuildContext context, AppState state) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xB3000000),
      builder: (sheetContext) => _QualitySheet(
        selected: state.quality,
        onSelect: (quality) {
          state.setQuality(quality);
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }
}

const _whatsAppGreen = Color(0xFF25D366);

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      semanticLabel: 'Nakili namba ya kifaa',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.greenA(0.1),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.greenA(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.copy, size: 14, color: AppColors.green),
            const SizedBox(width: 5),
            Text(
              'Nakili',
              style: uStyle(
                10,
                weight: FontWeight.w800,
                color: AppColors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualitySheet extends StatelessWidget {
  const _QualitySheet({required this.selected, required this.onSelect});

  final VideoQuality selected;
  final ValueChanged<VideoQuality> onSelect;

  static const _hints = {
    VideoQuality.auto: 'Inabadilika kulingana na intaneti yako',
    VideoQuality.p360: 'Chaguo la kawaida • inatumia bando kidogo',
    VideoQuality.p480: 'Picha nzuri • bando la wastani',
    VideoQuality.p720: 'HD • picha safi, inatumia bando kubwa',
    VideoQuality.p1080: 'Full HD • picha bora zaidi, bando kubwa sana',
  };

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.sheet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            border: Border(
              top: BorderSide(color: AppColors.line),
              left: BorderSide(color: AppColors.line),
              right: BorderSide(color: AppColors.line),
            ),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + safeBottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 17),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A423F),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text(
                  'Ubora wa video',
                  style: uStyle(17, weight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                for (final quality in VideoQuality.values) ...[
                  if (quality != VideoQuality.values.first)
                    const SizedBox(height: 8),
                  Pressable(
                    onTap: () => onSelect(quality),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: quality == selected
                            ? AppColors.greenA(0.06)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: quality == selected
                              ? AppColors.greenA(0.35)
                              : AppColors.line,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  quality.label,
                                  style: uStyle(12, weight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _hints[quality]!,
                                  style: uStyle(9, color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                          if (quality == selected)
                            const Icon(
                              LucideIcons.check,
                              size: 18,
                              color: AppColors.green,
                            ),
                        ],
                      ),
                    ),
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

class _ClearCacheSheet extends StatefulWidget {
  const _ClearCacheSheet();

  @override
  State<_ClearCacheSheet> createState() => _ClearCacheSheetState();
}

class _ClearCacheSheetState extends State<_ClearCacheSheet> {
  bool _clearing = false;

  Future<void> _clear() async {
    setState(() => _clearing = true);
    HapticFeedback.mediumImpact();
    await AppRestarter.clearCacheAndRestart(context);
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + safeBottom),
          decoration: const BoxDecoration(
            color: AppColors.sheet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            border: Border(
              top: BorderSide(color: AppColors.line),
              left: BorderSide(color: AppColors.line),
              right: BorderSide(color: AppColors.line),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A423F),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.greenA(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.refreshCw,
                    size: 26,
                    color: AppColors.green,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Futa akiba?',
                textAlign: TextAlign.center,
                style: uStyle(18, weight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Picha zilizohifadhiwa zitafutwa na programu itaanza upya '
                'ikiwa safi. Kifurushi chako na mipangilio havitaguswa.',
                textAlign: TextAlign.center,
                style: uStyle(11, color: AppColors.muted, height: 1.6),
              ),
              const SizedBox(height: 22),
              AppButton(
                label: 'Futa na anza upya',
                icon: LucideIcons.trash2,
                loading: _clearing,
                onTap: _clear,
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Ghairi',
                ghost: true,
                onTap: _clearing ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 25, 4, 9),
      child: Text(
        text,
        style: uStyle(
          9,
          weight: FontWeight.w800,
          color: AppColors.dim,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.iconColor = const Color(0xFFC7CFCC),
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: uStyle(12, weight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: uStyle(9, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
