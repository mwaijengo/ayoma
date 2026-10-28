import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/catalog.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class MalipoScreen extends StatelessWidget {
  const MalipoScreen({super.key, required this.onSelectPlan});

  final ValueChanged<Plan> onSelectPlan;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final subscription = state.subscription;
    final catalog = state.catalog;
    final plans = catalog.plans;
    final selectedId = subscription?.id ?? catalog.recommendedPlan.id;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VIFURUSHI',
                        style: uStyle(
                          8,
                          weight: FontWeight.w800,
                          color: AppColors.green,
                          letterSpacing: 0.96,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Malipo',
                        style: uStyle(
                          25,
                          weight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.shieldCheck,
                        size: 15,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Salama',
                        style: uStyle(
                          9,
                          weight: FontWeight.w700,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _CurrentPlanCard(
              subscription: subscription,
              onExtend: () => onSelectPlan(catalog.planById(subscription?.id) ?? catalog.recommendedPlan),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 27, 2, 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      subscription != null
                          ? 'Badilisha au ongeza muda'
                          : 'Chagua kifurushi',
                      style: uStyle(16, weight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    'Sitisha wakati wowote',
                    style: uStyle(8, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < plans.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _PlanCard(
                plan: plans[i],
                recommended: i == catalog.recommendedIndex,
                selected: plans[i].id == selectedId,
                onTap: () => onSelectPlan(plans[i]),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(3, 18, 3, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    LucideIcons.shieldCheck,
                    size: 18,
                    color: AppColors.dim,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Malipo salama na rahisi',
                          style: uStyle(
                            8,
                            weight: FontWeight.w700,
                            color: const Color(0xFF8F9995),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Kifurushi chako kimeunganishwa na simu hii.',
                          style: uStyle(7, color: AppColors.dim),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({required this.subscription, required this.onExtend});

  final Plan? subscription;
  final VoidCallback onExtend;

  @override
  Widget build(BuildContext context) {
    final active = subscription != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          GlowCard(
            radius: 20,
            borderColor: AppColors.greenA(0.2),
            glowCenter: const Alignment(0.8, -1),
            glowRadius: 0.58,
            glowAlpha: 0.13,
            gradient: const LinearGradient(
              begin: Alignment(-0.7, -1),
              end: Alignment(0.7, 1),
              stops: [0, 0.6],
              colors: [Color(0xFF182010), AppColors.surface],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const CrownOrb(size: 42, iconSize: 21),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'KIFURUSHI CHAKO',
                            style: uStyle(
                              7,
                              weight: FontWeight.w800,
                              color: AppColors.muted,
                              letterSpacing: 0.56,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subscription?.name ?? 'Bure',
                            style: uStyle(14, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.greenA(0.09),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: AppColors.greenA(0.16)),
                      ),
                      child: Text(
                        active ? 'KINATUMIKA' : 'BURE',
                        style: uStyle(
                          7,
                          weight: FontWeight.w800,
                          color: AppColors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                if (active)
                  CountdownBuilder(
                    builder: (context, remaining, fraction) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.clock3,
                              size: 16,
                              color: AppColors.green,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Muda uliobaki',
                              style: uStyle(
                                10,
                                weight: FontWeight.w700,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 11),
                        CountdownUnits(remaining: remaining),
                        const SizedBox(height: 14),
                        ProgressBar(
                          value: fraction.clamp(0.02, 1.0),
                          height: 5,
                          track: const Color(0x14FFFFFF),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.clock3,
                        size: 18,
                        color: AppColors.green,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '0',
                        style: uStyle(
                          38,
                          weight: FontWeight.w700,
                          letterSpacing: -2,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'siku zimebaki',
                        style: uStyle(10, color: AppColors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  const ProgressBar(
                    value: 0.02,
                    height: 5,
                    track: Color(0x14FFFFFF),
                  ),
                ],
                const SizedBox(height: 17),
                Pressable(
                  onTap: onExtend,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      color: AppColors.greenA(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.greenA(0.17)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          LucideIcons.clock3,
                          size: 17,
                          color: AppColors.green,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            active ? 'Ongeza muda' : 'Anza kifurushi',
                            style: uStyle(
                              10,
                              weight: FontWeight.w800,
                              color: AppColors.green,
                            ),
                          ),
                        ),
                        const Icon(
                          LucideIcons.chevronRight,
                          size: 18,
                          color: AppColors.green,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: -48,
            top: -48,
            child: IgnorePointer(
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.greenA(0.08)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.recommended,
    required this.selected,
    required this.onTap,
  });

  final Plan plan;
  final bool recommended;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: '${plan.name}, ${plan.price} kwa siku ${plan.days}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: recommended ? AppColors.greenA(0.35) : AppColors.line,
              ),
              color: recommended ? null : AppColors.surface,
              gradient: recommended
                  ? LinearGradient(
                      begin: const Alignment(-1, -0.2),
                      end: const Alignment(1, 0.2),
                      colors: [
                        Color.alphaBlend(
                          AppColors.greenA(0.06),
                          AppColors.surface,
                        ),
                        AppColors.surface,
                      ],
                    )
                  : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20,
                  height: 20,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppColors.green
                          : const Color(0xFF4A5450),
                    ),
                  ),
                  child: AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.green,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: uStyle(12, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Siku ${plan.days} • ${plan.description}',
                        style: uStyle(8, color: AppColors.muted),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.check,
                            size: 13,
                            color: AppColors.green,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              'Picha ${plan.quality}',
                              style: uStyle(
                                7,
                                weight: FontWeight.w600,
                                color: const Color(0xFFBDC6C2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 11),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      plan.price,
                      style: uStyle(
                        15,
                        weight: FontWeight.w700,
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '/siku ${plan.days}',
                      style: uStyle(6, color: AppColors.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (recommended)
            Positioned(
              right: 12,
              top: -7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.green,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'MAARUFU ZAIDI',
                  style: uStyle(
                    6,
                    weight: FontWeight.w800,
                    color: const Color(0xFF0A0F09),
                    letterSpacing: 0.24,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
