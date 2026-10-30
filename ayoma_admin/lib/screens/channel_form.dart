import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/image_field.dart';

const _categories = ['Mpira', 'Filamu', 'Tamthilia', 'Habari', 'Muziki', 'Katuni', 'Wanyama', 'Dini'];

/// "Name: value" per line <-> header map.
Map<String, String> parseHeaderLines(String text) {
  final map = <String, String>{};
  for (final line in text.split('\n')) {
    final i = line.indexOf(':');
    if (i <= 0) continue;
    final key = line.substring(0, i).trim();
    final value = line.substring(i + 1).trim();
    if (key.isNotEmpty && value.isNotEmpty) map[key] = value;
  }
  return map;
}

String headerLines(Map<String, String> headers) =>
    headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');

final _hex32 = RegExp(r'^[0-9a-fA-F]{32}$');
final _b64 = RegExp(r'^[A-Za-z0-9_\-+/]{20,24}={0,2}$');

/// Validates "kid:key" lines (hex or base64url). Returns an error or null.
String? validateClearKeys(String text) {
  final lines = text.split(RegExp(r'[\n,;]+')).map((l) => l.trim()).where((l) => l.isNotEmpty);
  for (final line in lines) {
    final parts = line.split(':');
    if (parts.length != 2) return 'Use one kid:key pair per line';
    for (final p in parts) {
      final v = p.trim().replaceAll('-', '');
      if (!_hex32.hasMatch(v) && !_b64.hasMatch(p.trim())) {
        return '"${p.trim()}" is not a 32-character hex or base64 key';
      }
    }
  }
  return null;
}

class ChannelForm extends StatefulWidget {
  const ChannelForm({super.key, this.channel});

  final Channel? channel;

  @override
  State<ChannelForm> createState() => _ChannelFormState();
}

class _ChannelFormState extends State<ChannelForm> {
  final _form = GlobalKey<FormState>();
  late final Channel _initial = widget.channel ?? Channel();

  late final _name = TextEditingController(text: _initial.name);
  late final _category = TextEditingController(text: _initial.category);
  late final _image = TextEditingController(text: _initial.imageUrl);
  late final _sort = TextEditingController(text: '${_initial.sortOrder}');
  late final _stream = TextEditingController(text: _initial.streamUrl);
  late final _clearKeys = TextEditingController(text: _initial.clearKeys);
  late final _referer = TextEditingController(text: _initial.referer);
  late final _origin = TextEditingController(text: _initial.origin);
  late final _userAgent = TextEditingController(text: _initial.userAgent);
  late final _headers = TextEditingController(text: headerLines(_initial.headers));

  late bool _premium = _initial.premium;
  late bool _live = _initial.live;
  late bool _active = _initial.active;
  late StreamType _streamType = _initial.streamType;
  late DrmType _drm = _initial.drmType;
  bool _busy = false;

  bool get _isNew => widget.channel == null;

  @override
  void dispose() {
    for (final c in [
      _name, _category, _image, _sort, _stream, _clearKeys, //
      _referer, _origin, _userAgent, _headers,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;

  String? _url(String? v, {bool required = false}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return required ? 'Required' : null;
    final uri = Uri.tryParse(s);
    if (uri == null || !uri.hasScheme || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      return 'Enter a full http(s) URL';
    }
    return null;
  }

  /// Links pasted without a scheme (e.g. site.com/live.php) are treated as http.
  static String _normalizeStream(String v) {
    final s = v.trim();
    return RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(s) ? s : 'http://$s';
  }

  /// Accepts any link with a host; headers after a `|` are allowed and ignored here.
  String? _streamUrl(String? v) {
    if ((v ?? '').trim().isEmpty) return 'Required';
    final link = _normalizeStream(v!).split('|').first.trim().replaceAll(' ', '%20');
    final uri = Uri.tryParse(link);
    if (uri == null || uri.host.isEmpty) return 'Enter a valid link, e.g. https://site.com/live.php';
    return null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      toast(context, 'Check the highlighted fields', error: true);
      return;
    }
    final channel = Channel(
      id: widget.channel?.id,
      name: _name.text.trim(),
      category: _category.text.trim(),
      imageUrl: _image.text.trim(),
      premium: _premium,
      live: _live,
      active: _active,
      sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
      streamUrl: _normalizeStream(_stream.text),
      streamType: _streamType,
      drmType: _drm,
      clearKeys: _drm == DrmType.clearkey ? _clearKeys.text.trim() : '',
      // No longer editable; kept so older channels that rely on them keep playing.
      licenseUrl: _drm == DrmType.none ? '' : _initial.licenseUrl,
      licenseHeaders: _drm == DrmType.none ? {} : _initial.licenseHeaders,
      referer: _referer.text.trim(),
      origin: _origin.text.trim(),
      userAgent: _userAgent.text.trim(),
      headers: parseHeaderLines(_headers.text),
    );
    setState(() => _busy = true);
    final api = SessionScope.read(context).api;
    final ok = await runAction(
      context,
      () => api.saveChannel(channel),
      success: _isNew ? 'Channel added' : 'Channel saved',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${_initial.name}?',
      message: 'The channel disappears from every app. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = SessionScope.read(context).api;
    final done = await runAction(context, () => api.deleteChannel(_initial.id!), success: 'Channel deleted');
    if (done && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(_isNew ? 'Add channel' : 'Edit channel', style: uStyle(18, weight: FontWeight.w800)),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Delete',
              onPressed: _busy ? null : _delete,
              icon: const Icon(LucideIcons.trash2, size: 20, color: AppColors.error),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              children: [
                const SectionLabel('Channel'),
                Panel(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _name,
                        validator: _required,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(LucideIcons.tv, size: 18)),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _category,
                        validator: _required,
                        decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(LucideIcons.tag, size: 18)),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final c in _categories)
                              ActionChip(
                                label: Text(c),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() => _category.text = c),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ImageField(controller: _image, validator: (v) => _url(v)),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _sort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Sort order', helperText: 'Lower shows first'),
                      ),
                      const SizedBox(height: 8),
                      SwitchRow(
                        title: 'Paid channel (MALIPO)',
                        subtitle: 'Only users with an active package can watch',
                        value: _premium,
                        onChanged: (v) => setState(() => _premium = v),
                      ),
                      SwitchRow(
                        title: 'Live badge',
                        subtitle: 'Shows MUBASHARA on the card',
                        value: _live,
                        onChanged: (v) => setState(() => _live = v),
                      ),
                      SwitchRow(
                        title: 'Visible in app',
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                      ),
                    ],
                  ),
                ),
                const SectionLabel('Stream'),
                Panel(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _stream,
                        validator: _streamUrl,
                        keyboardType: TextInputType.url,
                        maxLines: null,
                        decoration: const InputDecoration(
                          labelText: 'Stream URL',
                          hintText: 'https://…',
                          prefixIcon: Icon(LucideIcons.link, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<StreamType>(
                        initialValue: _streamType,
                        isExpanded: true,
                        dropdownColor: AppColors.surface2,
                        decoration: const InputDecoration(
                          labelText: 'Stream type',
                          prefixIcon: Icon(LucideIcons.radio, size: 18),
                        ),
                        items: [
                          for (final t in StreamType.values)
                            DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (t) => setState(() => _streamType = t ?? StreamType.auto),
                      ),
                    ],
                  ),
                ),
                const SectionLabel('DRM protection'),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<DrmType>(
                        segments: [
                          for (final d in DrmType.values) ButtonSegment(value: d, label: Text(d.label)),
                        ],
                        selected: {_drm},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => setState(() => _drm = s.first),
                      ),
                      const SizedBox(height: 12),
                      ..._drmFields(),
                    ],
                  ),
                ),
                const SectionLabel('Request headers'),
                Panel(
                  child: Column(
                    children: [
                      Text(
                        'Sent with every manifest, segment and licence request. Use these when the stream '
                        'only plays from a specific website.',
                        style: uStyle(12.5, color: AppColors.muted, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _referer,
                        validator: (v) => _url(v),
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Referer',
                          hintText: 'https://example.com/',
                          prefixIcon: Icon(LucideIcons.cornerDownRight, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _origin,
                        validator: (v) => _url(v),
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Origin',
                          hintText: 'https://example.com',
                          prefixIcon: Icon(LucideIcons.globe, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _userAgent,
                        decoration: const InputDecoration(
                          labelText: 'User-Agent (optional)',
                          prefixIcon: Icon(LucideIcons.monitorSmartphone, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _headers,
                        minLines: 2,
                        maxLines: 6,
                        validator: _headerValidator,
                        decoration: const InputDecoration(
                          labelText: 'Other headers',
                          hintText: 'X-Token: abc123\nCookie: session=xyz',
                          helperText: 'One "Name: value" per line',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.ink))
                : const Icon(LucideIcons.check, size: 18),
            label: Text(_isNew ? 'Add channel' : 'Save changes'),
          ),
        ),
      ),
    );
  }

  String? _headerValidator(String? v) {
    for (final line in (v ?? '').split('\n')) {
      if (line.trim().isEmpty) continue;
      final i = line.indexOf(':');
      if (i <= 0 || line.substring(i + 1).trim().isEmpty) return 'Use "Name: value" on each line';
    }
    return null;
  }

  List<Widget> _drmFields() {
    switch (_drm) {
      case DrmType.none:
        return [
          Text(
            'Plain HLS, DASH or MP4 stream without encryption.',
            style: uStyle(12.5, color: AppColors.muted, height: 1.4),
          ),
        ];
      case DrmType.clearkey:
        return [
          TextFormField(
            controller: _clearKeys,
            minLines: 2,
            maxLines: 6,
            style: uStyle(13, weight: FontWeight.w600).copyWith(fontFamily: 'monospace'),
            validator: (v) {
              final keys = (v ?? '').trim();
              return keys.isEmpty ? 'Add at least one kid:key pair' : validateClearKeys(keys);
            },
            decoration: const InputDecoration(
              labelText: 'ClearKey (kid:key)',
              hintText: 'feedf00deedeadbeeff0baadf00dd00d:00112233445566778899aabbccddeeff',
              helperText: 'One pair per line, hex (32 characters) or base64url',
              alignLabelWithHint: true,
            ),
          ),
        ];
      case DrmType.widevine:
        return [
          Text(
            'The player gets the Widevine licence automatically from the stream.',
            style: uStyle(12.5, color: AppColors.muted, height: 1.4),
          ),
        ];
    }
  }
}
