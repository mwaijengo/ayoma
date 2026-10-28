import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/image_field.dart';

class SlidesScreen extends StatefulWidget {
  const SlidesScreen({super.key});

  @override
  State<SlidesScreen> createState() => _SlidesScreenState();
}

class _SlidesScreenState extends State<SlidesScreen> {
  final _listKey = GlobalKey<AsyncListState<(List<Slide>, List<Channel>)>>();

  Future<void> _edit(List<Channel> channels, [Slide? slide]) async {
    final saved = await showFormSheet<bool>(
      context,
      title: slide == null ? 'Add banner' : 'Edit banner',
      child: _SlideForm(slide: slide, channels: channels),
    );
    if (saved == true) _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.read(context).api;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('Carousel', style: uStyle(18, weight: FontWeight.w800)),
      ),
      body: AsyncList<(List<Slide>, List<Channel>)>(
        key: _listKey,
        load: () async => (await api.slides(), await api.channels()),
        builder: (context, data, reload) {
          final (slides, channels) = data;
          return [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Banners rotate at the top of the home screen. Tapping one can open a channel.',
                      style: uStyle(13, color: AppColors.muted, height: 1.4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _edit(channels),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
            if (slides.isEmpty)
              const EmptyState(icon: LucideIcons.galleryHorizontal, title: 'No banners yet')
            else
              for (final s in slides)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Opacity(
                    opacity: s.active ? 1 : 0.5,
                    child: Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _edit(channels, s),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(aspectRatio: 16 / 7, child: NetImage(s.imageUrl, radius: 0)),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.title.isEmpty ? 'Banner #${s.id}' : s.title,
                                          style: uStyle(14.5, weight: FontWeight.w800),
                                        ),
                                        Text(
                                          [
                                            'Order ${s.sortOrder}',
                                            if (s.channelId != null)
                                              'Opens ${channels.where((c) => c.id == s.channelId).firstOrNull?.name ?? 'channel #${s.channelId}'}',
                                            if (!s.active) 'Hidden',
                                          ].join(' • '),
                                          style: uStyle(12, color: AppColors.muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(LucideIcons.trash2, size: 18, color: AppColors.error),
                                    onPressed: () async {
                                      final ok = await confirmDialog(
                                        context,
                                        title: 'Delete banner?',
                                        message: 'It is removed from the home screen of every app.',
                                        confirmLabel: 'Delete',
                                        destructive: true,
                                      );
                                      if (!ok || !context.mounted) return;
                                      final done = await runAction(context, () => api.deleteSlide(s.id!), success: 'Banner deleted');
                                      if (done) await reload();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ];
        },
      ),
    );
  }
}

class _SlideForm extends StatefulWidget {
  const _SlideForm({this.slide, required this.channels});

  final Slide? slide;
  final List<Channel> channels;

  @override
  State<_SlideForm> createState() => _SlideFormState();
}

class _SlideFormState extends State<_SlideForm> {
  late final Slide _s = widget.slide ?? Slide();
  late final _image = TextEditingController(text: _s.imageUrl);
  late final _title = TextEditingController(text: _s.title);
  late final _kicker = TextEditingController(text: _s.kicker);
  late final _detail = TextEditingController(text: _s.detail);
  late final _sort = TextEditingController(text: '${_s.sortOrder}');
  late int? _channelId = _s.channelId;
  late bool _active = _s.active;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_image, _title, _kicker, _detail, _sort]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _validImage {
    final uri = Uri.tryParse(_image.text.trim());
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  Future<void> _save() async {
    final api = SessionScope.read(context).api;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => api.saveSlide(
        Slide(
          id: _s.id,
          imageUrl: _image.text.trim(),
          title: _title.text.trim(),
          kicker: _kicker.text.trim(),
          detail: _detail.text.trim(),
          channelId: _channelId,
          sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
          active: _active,
        ),
      ),
      success: 'Banner saved',
    );
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
        ImageField(
          controller: _image,
          aspectRatio: 16 / 7,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title (for your reference)'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          initialValue: _channelId,
          isExpanded: true,
          dropdownColor: AppColors.surface2,
          decoration: const InputDecoration(labelText: 'Opens channel', prefixIcon: Icon(LucideIcons.tv, size: 18)),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Nothing (image only)')),
            for (final c in widget.channels) DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() => _channelId = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _sort,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Sort order', helperText: 'Lower shows first'),
        ),
        const SizedBox(height: 8),
        SwitchRow(title: 'Visible in app', value: _active, onChanged: (v) => setState(() => _active = v)),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy || !_validImage ? null : _save, child: const Text('Save banner')),
      ],
    );
  }
}
