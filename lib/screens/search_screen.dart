import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/catalog.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.onPlay});

  final ValueChanged<Channel> onPlay;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final channels = AppScope.of(context).catalog.channels;
    final results = channels
        .where((c) => '${c.name} ${c.category}'.toLowerCase().contains(q))
        .toList();

    return SafeArea(
      bottom: false,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tafuta chaneli',
                style: uStyle(25, weight: FontWeight.w800, letterSpacing: -1),
              ),
              const SizedBox(height: 20),
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.search,
                      size: 19,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onChanged: (value) => setState(() => _query = value),
                        textInputAction: TextInputAction.search,
                        style: uStyle(12, color: Colors.white),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: 'Tafuta mpira, filamu, chaneli...',
                          hintStyle: uStyle(12, color: AppColors.muted),
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(
                            LucideIcons.x,
                            size: 17,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SectionHeading(
                title: _query.isNotEmpty
                    ? 'Chaneli ${results.length} zimepatikana'
                    : 'Chaneli zote (${channels.length})',
                margin: const EdgeInsets.fromLTRB(0, 24, 0, 14),
              ),
              if (results.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      const Icon(
                        LucideIcons.search,
                        size: 30,
                        color: AppColors.faint,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Hakuna chaneli inayolingana na "${_query.trim()}"',
                        textAlign: TextAlign.center,
                        style: uStyle(12, color: AppColors.muted),
                      ),
                    ],
                  ),
                )
              else
                ChannelGrid(channels: results, onPlay: widget.onPlay),
            ],
          ),
        ),
      ),
    );
  }
}
