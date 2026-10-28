import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/catalog.dart';
import '../services/api.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Shows the checkout sheet. Resolves to `true` when a plan was activated.
Future<bool> showPaymentSheet(BuildContext context, Plan plan) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB3000000),
    builder: (_) => PaymentSheet(plan: plan),
  );
  return result ?? false;
}

class PaymentSheet extends StatefulWidget {
  const PaymentSheet({super.key, required this.plan});

  final Plan plan;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

enum _Stage { form, waiting, done }

class _PaymentSheetState extends State<PaymentSheet> {
  static const _pollEvery = Duration(seconds: 3);
  static const _pollFor = Duration(minutes: 2);

  late final AppState _state = AppScope.read(context);
  late final _name = TextEditingController(text: _state.subscriberName);
  late final _phone = TextEditingController(text: _state.subscriberPhone);
  final _phoneFocus = FocusNode();
  late Plan _plan = widget.plan;
  bool _planMenuOpen = false;
  _Stage _stage = _Stage.form;
  bool _submitting = false;
  bool _checking = false;
  String _error = '';
  int? _paymentId;
  Timer? _poll;
  DateTime? _pollUntil;

  bool get _submitted => _stage == _Stage.done;

  @override
  void dispose() {
    _poll?.cancel();
    _name.dispose();
    _phone.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final phone = _phone.text;
    if (name.split(RegExp(r'\s+')).length < 2) {
      setState(() => _error = 'Tafadhali andika jina lako kamili.');
      return;
    }
    if (!RegExp(r'^0\d{9}$').hasMatch(phone)) {
      setState(
        () => _error = 'Namba ya simu ianze na 0 na iwe na tarakimu 10.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = '';
      _submitting = true;
    });

    final api = _state.api;
    if (api == null) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      await _state.activate(_plan, name: name, phone: phone);
      if (!mounted) return;
      _finish();
      return;
    }

    try {
      await _state.rememberPayer(name: name, phone: phone);
      final payment = await api.startPayment(
        planId: _plan.id,
        name: name,
        phone: phone,
      );
      if (!mounted) return;
      _paymentId = (payment['id'] as num).toInt();
      _pollUntil = DateTime.now().add(_pollFor);
      setState(() {
        _submitting = false;
        _stage = _Stage.waiting;
      });
      _poll = Timer.periodic(_pollEvery, (_) => _check());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    }
  }

  Future<void> _check({bool manual = false}) async {
    final id = _paymentId;
    final api = _state.api;
    if (id == null || api == null || _checking) return;
    if (!manual && DateTime.now().isAfter(_pollUntil!)) {
      _backToForm(
        'Hatukupokea uthibitisho wa malipo. Kama umeshalipa, '
        'kifurushi kitaanza punde. Vinginevyo jaribu tena.',
      );
      _state.sync(force: true);
      return;
    }
    if (manual) setState(() => _checking = true);
    _checking = true;
    try {
      final res = await api.paymentStatus(id);
      if (!mounted || _stage != _Stage.waiting) return;
      final payment = (res['payment'] as Map).cast<String, dynamic>();
      switch (payment['status']) {
        case 'paid':
          if (res['user'] is Map) {
            _state.applyServerUser(
              (res['user'] as Map).cast<String, dynamic>(),
            );
          }
          _finish();
        case 'failed':
          final message = '${payment['message'] ?? ''}';
          _backToForm(
            message.isEmpty
                ? 'Malipo hayakukamilika. Tafadhali jaribu tena.'
                : message,
          );
      }
    } on ApiException catch (e) {
      if (manual && mounted) showAppToast(context, e.message);
    } finally {
      _checking = false;
      if (manual && mounted) setState(() {});
    }
  }

  void _backToForm(String error) {
    _poll?.cancel();
    _paymentId = null;
    if (!mounted) return;
    setState(() {
      _stage = _Stage.form;
      _error = error;
    });
  }

  void _finish() {
    _poll?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _submitting = false;
      _stage = _Stage.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
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
              padding: EdgeInsets.fromLTRB(20, 10, 20, 24 + safeBottom),
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
                  _header(context),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: switch (_stage) {
                        _Stage.form => _form(context),
                        _Stage.waiting => _waiting(context),
                        _Stage.done => _success(context),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.green,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(LucideIcons.crown, size: 21, color: AppColors.ink),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (_stage) {
                _Stage.form => 'Lipia sasa',
                _Stage.waiting => 'Thibitisha malipo',
                _Stage.done => 'Malipo yamekamilika',
              }, style: uStyle(17, weight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(switch (_stage) {
                _Stage.form => 'Lipa mara moja, tazama chaneli zote',
                _Stage.waiting => 'Inasubiri uthibitisho kutoka mtandao wako',
                _Stage.done => 'Furahia chaneli zote za AyomaMax',
              }, style: uStyle(9, color: AppColors.muted)),
            ],
          ),
        ),
        CircleIconButton(
          icon: LucideIcons.x,
          label: 'Funga',
          onTap: () => Navigator.of(context).pop(_submitted),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 22, 0, 7),
          child: Text(
            'CHAGUA KIFURUSHI',
            style: uStyle(
              8,
              weight: FontWeight.w800,
              color: AppColors.muted,
              letterSpacing: 0.64,
            ),
          ),
        ),
        _PlanOption(
          plan: _plan,
          selected: true,
          expanded: _planMenuOpen,
          onTap: () => setState(() => _planMenuOpen = !_planMenuOpen),
        ),
        if (_planMenuOpen)
          for (final plan in _state.catalog.plans)
            if (plan.id != _plan.id) ...[
              const SizedBox(height: 8),
              _PlanOption(
                plan: plan,
                selected: false,
                onTap: () => setState(() {
                  _plan = plan;
                  _planMenuOpen = false;
                }),
              ),
            ],
        const SizedBox(height: 17),
        _Field(
          label: 'JINA KAMILI',
          icon: LucideIcons.circleUserRound,
          controller: _name,
          hint: 'mf. Ahmed Ali',
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _phoneFocus.requestFocus(),
          onChanged: (_) => _clearError(),
        ),
        _Field(
          label: 'NAMBA YA SIMU',
          icon: LucideIcons.smartphone,
          controller: _phone,
          focusNode: _phoneFocus,
          hint: '07XX XXX XXX',
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) => _clearError(),
        ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Text(_error, style: uStyle(10, color: AppColors.error)),
          ),
        const SizedBox(height: 4),
        AppButton(
          label: 'Endelea kwa usalama',
          icon: LucideIcons.lockKeyhole,
          loading: _submitting,
          onTap: _submit,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.shieldCheck, size: 15, color: AppColors.dim),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                _state.online
                    ? 'Utapokea ombi la kuweka PIN kwenye simu yako.'
                    : 'Huu ni mfano tu. Hakuna pesa itakayokatwa.',
                style: uStyle(8, color: AppColors.dim),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _waiting(BuildContext context) {
    return Padding(
      key: const ValueKey('waiting'),
      padding: const EdgeInsets.fromLTRB(8, 30, 8, 5),
      child: Column(
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.green,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Weka PIN kwenye simu yako',
            textAlign: TextAlign.center,
            style: uStyle(17, weight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'Tumetuma ombi la ${_plan.price} kwenda ${_phone.text}. '
              'Fungua ujumbe kwenye simu yako na uweke PIN kuthibitisha.',
              textAlign: TextAlign.center,
              style: uStyle(11, color: AppColors.muted, height: 1.7),
            ),
          ),
          const SizedBox(height: 22),
          AppButton(
            label: 'Nimeshalipa, angalia',
            icon: LucideIcons.refreshCw,
            loading: _checking,
            onTap: () => _check(manual: true),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => _backToForm(''),
            child: Text(
              'Badilisha namba',
              style: uStyle(11, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  void _clearError() {
    if (_error.isNotEmpty) setState(() => _error = '');
  }

  Widget _success(BuildContext context) {
    final firstName = _name.text.trim().split(RegExp(r'\s+')).first;
    return Padding(
      key: const ValueKey('success'),
      padding: const EdgeInsets.fromLTRB(8, 32, 8, 5),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.elasticOut,
            builder: (_, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.green,
              ),
              child: const Icon(
                LucideIcons.check,
                size: 32,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 17),
          Text(
            'Asante, $firstName',
            textAlign: TextAlign.center,
            style: uStyle(20, weight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              _state.online
                  ? 'Kifurushi chako cha ${_plan.name} kimeanza kwenye simu hii.'
                  : 'Kifurushi chako cha ${_plan.name} kimeanza kwenye simu hii. '
                        'Huu ni mfano tu, hakuna pesa iliyokatwa.',
              textAlign: TextAlign.center,
              style: uStyle(11, color: AppColors.muted, height: 1.7),
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            label: 'Rudi kwenye chaneli',
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.plan,
    required this.selected,
    required this.onTap,
    this.expanded,
  });

  final Plan plan;
  final bool selected;
  final VoidCallback onTap;

  /// Non-null for the dropdown header; shows an arrow reflecting its state.
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: expanded == null
          ? '${plan.name}, ${plan.price}'
          : 'Kifurushi: ${plan.name}, ${plan.price}. Gusa kubadilisha',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? AppColors.greenA(0.055) : AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.greenA(0.25) : AppColors.line,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.green : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.green : const Color(0xFF4A5450),
                ),
              ),
              child: selected
                  ? const Icon(
                      LucideIcons.check,
                      size: 18,
                      color: Color(0xFF0A1008),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kifurushi cha ${plan.name} (siku ${plan.days})',
                    style: uStyle(11, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${plan.description} • ${plan.quality}',
                    style: uStyle(8, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              plan.price,
              style: uStyle(
                14,
                weight: FontWeight.w700,
                color: selected ? AppColors.green : AppColors.text,
              ),
            ),
            if (expanded != null) ...[
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: expanded! ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: AppColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.icon,
    required this.controller,
    required this.hint,
    this.focusNode,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 3, bottom: 7),
            child: Text(
              widget.label,
              style: uStyle(
                8,
                weight: FontWeight.w800,
                color: AppColors.muted,
                letterSpacing: 0.64,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: _focus.hasFocus ? AppColors.green : AppColors.line,
              ),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 19, color: AppColors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    keyboardType: widget.keyboardType,
                    textCapitalization: widget.textCapitalization,
                    autofillHints: widget.autofillHints,
                    inputFormatters: widget.inputFormatters,
                    textInputAction: widget.textInputAction,
                    onSubmitted: widget.onSubmitted,
                    onChanged: widget.onChanged,
                    style: uStyle(12, color: Colors.white),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: widget.hint,
                      hintStyle: uStyle(12, color: AppColors.muted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
