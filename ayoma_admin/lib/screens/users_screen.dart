import 'dart:async';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/admin_api.dart';
import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'user_sheets.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _listKey = GlobalKey<AsyncListState<UserPage>>();
  final _search = TextEditingController();
  Timer? _debounce;
  String _filter = 'all';

  static const _filters = [
    ('all', 'All'),
    ('premium', 'Premium'),
    ('expiring', 'Expiring'),
    ('expired', 'Expired'),
    ('free', 'Free'),
    ('blocked', 'Blocked'),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _reload() => _listKey.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.read(context).api;
    return Column(
      children: [
        const PageHeader(title: 'Users', subtitle: 'Devices using the AyomaMax app'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), _reload);
            },
            decoration: const InputDecoration(
              hintText: 'Search device ID, name or phone',
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
              for (final (id, label) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _filter == id,
                    onSelected: (_) {
                      setState(() => _filter = id);
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncList<UserPage>(
            key: _listKey,
            load: () => api.users(search: _search.text.trim(), filter: _filter),
            builder: (context, page, reload) => [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                child: Text(
                  page.total > page.users.length
                      ? 'Showing ${page.users.length} of ${page.total} users'
                      : '${page.total} user${page.total == 1 ? '' : 's'}',
                  style: uStyle(13, color: AppColors.muted),
                ),
              ),
              if (page.users.isEmpty)
                const EmptyState(
                  icon: LucideIcons.users,
                  title: 'No users here',
                  message: 'Users appear after they open the app.',
                )
              else
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [for (final u in page.users) _UserTile(user: u, onChanged: reload)],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.onChanged});

  final AppUser user;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final u = user;
    return ListTile(
      onTap: () => showUserSheet(context, u.id, onChanged: onChanged),
      leading: UserAvatar(u),
      title: Text(u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: uStyle(14.5, weight: FontWeight.w700)),
      subtitle: Text(
        u.status == UserStatus.premium || u.status == UserStatus.expired
            ? '${u.planName ?? 'Package'} • ${timeLeft(u.expiresAt)}'
            : 'Seen ${timeAgo(u.lastSeenAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: uStyle(12, color: AppColors.muted),
      ),
      trailing: Pill(u.status.label.toUpperCase(), color: userStatusColor(u.status)),
    );
  }
}
