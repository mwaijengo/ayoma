import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _listKey = GlobalKey<AsyncListState<List<Plan>>>();

  Future<void> _edit([Plan? plan]) async {
    final saved = await showFormSheet<bool>(
      context,
      title: plan == null ? 'New package' : 'Edit ${plan.name}',
      child: _PlanForm(plan: plan),
    );
    if (saved == true) _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.read(context).api;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('Packages & prices', style: uStyle(18, weight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'New package', onPressed: _edit, icon: const Icon(LucideIcons.plus)),
        ],
      ),
      body: AsyncList<List<Plan>>(
        key: _listKey,
        load: api.plans,
        builder: (context, plans, reload) => [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              'Prices update in every app on its next sync. Users who already paid keep their days.',
              style: uStyle(13, color: AppColors.muted, height: 1.4),
            ),
          ),
          if (plans.isEmpty) const EmptyState(icon: LucideIcons.package, title: 'No packages'),
          for (final p in plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Opacity(
                opacity: p.active ? 1 : 0.5,
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _edit(p),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: p.recommended ? AppColors.greenA(0.45) : AppColors.line),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(child: Text(p.name, style: uStyle(16, weight: FontWeight.w800))),
                                    const SizedBox(width: 8),
                                    if (p.recommended) const Pill('POPULAR', color: AppColors.green),
                                    if (!p.active) const Pill('HIDDEN'),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                if (p.description.isNotEmpty)
                                  Text(p.description, style: uStyle(12.5, color: AppColors.text)),
                                Text(
                                  '${p.days} days • ${p.quality} • id: ${p.id}',
                                  style: uStyle(12.5, color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                          Text(formatTzs(p.priceTzs), style: uStyle(17, weight: FontWeight.w800, color: AppColors.green)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanForm extends StatefulWidget {
  const _PlanForm({this.plan});

  final Plan? plan;

  @override
  State<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends State<_PlanForm> {
  final _form = GlobalKey<FormState>();
  late final Plan _p = widget.plan ?? Plan();
  late final _id = TextEditingController(text: _p.id);
  late final _name = TextEditingController(text: _p.name);
  late final _days = TextEditingController(text: '${_p.days}');
  late final _price = TextEditingController(text: widget.plan == null ? '' : '${_p.priceTzs}');
  late final _quality = TextEditingController(text: _p.quality);
  late final _description = TextEditingController(text: _p.description);
  late final _sort = TextEditingController(text: '${_p.sortOrder}');
  late bool _recommended = _p.recommended;
  late bool _active = _p.active;
  bool _busy = false;

  bool get _isNew => widget.plan == null;

  @override
  void dispose() {
    for (final c in [_id, _name, _days, _price, _quality, _description, _sort]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = SessionScope.read(context).api;
    final plan = Plan(
      id: _id.text.trim(),
      name: _name.text.trim(),
      days: int.parse(_days.text.trim()),
      priceTzs: int.parse(_price.text.trim().replaceAll(',', '')),
      quality: _quality.text.trim().isEmpty ? 'HD' : _quality.text.trim(),
      description: _description.text.trim(),
      recommended: _recommended,
      active: _active,
      sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
    );
    setState(() => _busy = true);
    final ok = await runAction(context, () => api.savePlan(plan, isNew: _isNew), success: 'Package saved');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${_p.name}?',
      message: 'If users have paid for it, it is hidden instead so payment history stays correct.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = SessionScope.read(context).api;
    var hidden = false;
    final done = await runAction(context, () async => hidden = await api.deletePlan(_p.id));
    if (!done || !mounted) return;
    toast(context, hidden ? 'Package hidden (it has payments)' : 'Package deleted');
    Navigator.pop(context, true);
  }

  String? _positiveInt(String? v, {bool allowZero = false}) {
    final n = int.tryParse((v ?? '').trim().replaceAll(',', ''));
    if (n == null || n < (allowZero ? 0 : 1)) return 'Enter a number';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (_isNew) ...[
            TextFormField(
              controller: _id,
              validator: (v) =>
                  RegExp(r'^[a-z0-9_]{2,30}$').hasMatch((v ?? '').trim()) ? null : 'Lowercase letters, numbers and _ only',
              decoration: const InputDecoration(
                labelText: 'Package ID',
                hintText: 'e.g. siku_3',
                helperText: 'Permanent; cannot be changed later',
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _name,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            decoration: const InputDecoration(labelText: 'Name shown in app', hintText: 'e.g. Mwezi 1'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Short description', hintText: 'e.g. Chaneli zote, bila matangazo'),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _price,
                  validator: (v) => _positiveInt(v, allowZero: true),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Price (TSh)', prefixIcon: Icon(LucideIcons.banknote, size: 18)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _days,
                  validator: _positiveInt,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Days', prefixIcon: Icon(LucideIcons.calendarDays, size: 18)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(controller: _quality, decoration: const InputDecoration(labelText: 'Quality label')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _sort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sort order'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchRow(
            title: 'Most popular',
            subtitle: 'Highlighted in the app; only one package can have it',
            value: _recommended,
            onChanged: (v) => setState(() => _recommended = v),
          ),
          SwitchRow(
            title: 'Available for purchase',
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_isNew ? 'Create package' : 'Save package')),
          if (!_isNew) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : _delete,
              icon: const Icon(LucideIcons.trash2, size: 16),
              label: const Text('Delete package'),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}
