import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'channel_form.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  final _listKey = GlobalKey<AsyncListState<List<Channel>>>();
  String _query = '';

  Future<void> _open([Channel? channel]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ChannelForm(channel: channel)),
    );
    if (saved == true) _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.read(context).api;
    return Column(
      children: [
        PageHeader(
          title: 'Channels',
          subtitle: 'Streams shown in the app',
          actions: [
            FilledButton.icon(
              onPressed: _open,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Add'),
            ),
            const SizedBox(width: 6),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: 'Filter by name or category',
              prefixIcon: Icon(LucideIcons.search, size: 18),
            ),
          ),
        ),
        Expanded(
          child: AsyncList<List<Channel>>(
            key: _listKey,
            load: api.channels,
            builder: (context, all, reload) {
              final channels = _query.isEmpty
                  ? all
                  : all
                        .where((c) => c.name.toLowerCase().contains(_query) || c.category.toLowerCase().contains(_query))
                        .toList();
              final premium = all.where((c) => c.premium).length;
              return [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                  child: Text(
                    '${all.length} channels • ${all.where((c) => c.active).length} active • $premium paid',
                    style: uStyle(13, color: AppColors.muted),
                  ),
                ),
                if (all.isEmpty)
                  EmptyState(
                    icon: LucideIcons.tv,
                    title: 'Hakuna channel kwasasa',
                    action: FilledButton(onPressed: _open, child: const Text('Add channel')),
                  )
                else
                  for (final c in channels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ChannelTile(channel: c, onEdit: () => _open(c), onChanged: reload),
                    ),
              ];
            },
          ),
        ),
      ],
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel, required this.onEdit, required this.onChanged});

  final Channel channel;
  final VoidCallback onEdit;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final c = channel;
    final api = SessionScope.read(context).api;
    return Opacity(
      opacity: c.active ? 1 : 0.55,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                NetImage(c.imageUrl, width: 88, height: 60),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: uStyle(15, weight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        '${c.category} • ${c.streamType.name.toUpperCase()}',
                        style: uStyle(12, color: AppColors.muted),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          if (c.premium) const Pill('MALIPO', color: AppColors.green, icon: LucideIcons.crown),
                          if (c.drmType != DrmType.none)
                            Pill(c.drmType.label.toUpperCase(), color: AppColors.blue, icon: LucideIcons.keyRound),
                          if (c.referer.isNotEmpty || c.origin.isNotEmpty || c.headers.isNotEmpty)
                            const Pill('HEADERS', color: AppColors.amber),
                          if (c.live) const Pill('LIVE', color: AppColors.red),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Switch(
                      value: c.active,
                      onChanged: (v) async {
                        final ok = await runAction(
                          context,
                          () => api.setChannelActive(c.id!, v),
                          success: v ? '${c.name} is visible' : '${c.name} is hidden',
                        );
                        if (ok) await onChanged();
                      },
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(LucideIcons.ellipsis, size: 18, color: AppColors.muted),
                      color: AppColors.surface2,
                      onSelected: (v) async {
                        if (v == 'edit') return onEdit();
                        final ok = await confirmDialog(
                          context,
                          title: 'Delete ${c.name}?',
                          message: 'The channel disappears from every app. This cannot be undone.',
                          confirmLabel: 'Delete',
                          destructive: true,
                        );
                        if (!ok || !context.mounted) return;
                        final done = await runAction(context, () => api.deleteChannel(c.id!), success: 'Channel deleted');
                        if (done) await onChanged();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
