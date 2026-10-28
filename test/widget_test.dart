import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ayoma/data/catalog.dart';
import 'package:ayoma/main.dart';
import 'package:ayoma/screens/splash_screen.dart';
import 'package:ayoma/state/app_state.dart';

final builtIn = Catalog.builtIn;

Future<void> pumpPastSplash(WidgetTester tester) async {
  await tester.pump(SplashGate.duration);
  await tester.pump(const Duration(milliseconds: 500));
}

/// Tab changes restart the app behind the quick splash.
Future<void> switchTab(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pump();
  expect(find.byType(SplashScreen), findsOneWidget);
  await pumpPastSplash(tester);
  expect(find.byType(SplashScreen), findsNothing);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows home and switches tabs', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final state = await AppState.load();
    await tester.pumpWidget(AyomaApp(state: state));
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);
    await pumpPastSplash(tester);
    expect(find.byType(SplashScreen), findsNothing);

    expect(find.text('Chagua chaneli'), findsOneWidget);
    expect(find.text('Ligi ya Mabingwa'), findsNothing);
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel('Ligi ya Mabingwa'), findsWidgets);
    semantics.dispose();
    expect(find.text(builtIn.channels.last.name), findsNothing);

    await switchTab(tester, find.text('Ona zote'));
    expect(find.text('Chaneli zote (${builtIn.channels.length})'), findsOneWidget);
    for (final channel in builtIn.channels) {
      expect(find.text(channel.name), findsOneWidget);
    }

    await switchTab(tester, find.text('Malipo'));
    expect(find.text('Chagua kifurushi'), findsOneWidget);

    await switchTab(tester, find.text('Settings').last);
    expect(find.text(state.deviceId), findsOneWidget);

    expect(state.quality, VideoQuality.p360);
    expect(find.text('360p'), findsOneWidget);
    await tester.tap(find.text('Ubora wa video'));
    await tester.pumpAndSettle();
    for (final quality in VideoQuality.values) {
      expect(find.text(quality.label), findsWidgets);
    }
    await tester.tap(find.text('1080p'));
    await tester.pumpAndSettle();
    expect(state.quality, VideoQuality.p1080);
    expect(find.text('1080p'), findsOneWidget);
  });

  testWidgets('pulling down on home replays the splash', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final state = await AppState.load();
    await tester.pumpWidget(AyomaApp(state: state));
    await pumpPastSplash(tester);
    expect(find.byType(SplashScreen), findsNothing);

    await tester.fling(find.text('Chagua chaneli'), const Offset(0, 400), 1200);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SplashScreen), findsOneWidget);

    await pumpPastSplash(tester);
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('Chagua chaneli'), findsOneWidget);
  });

  for (final (daysLeft, shown) in [(2, true), (10, false)]) {
    testWidgets('renewal reminder with $daysLeft days left: $shown', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final expiresAt = DateTime.now().add(Duration(days: daysLeft));
      SharedPreferences.setMockInitialValues({
        'ayoma.planId': builtIn.plans.last.id,
        'ayoma.expiresAt': expiresAt.millisecondsSinceEpoch,
        'ayoma.periodDays': builtIn.plans.last.days,
      });
      final state = await AppState.load();
      await tester.pumpWidget(AyomaApp(state: state));
      await pumpPastSplash(tester);

      final matcher = shown ? findsOneWidget : findsNothing;
      expect(
        find.textContaining('Umebakiwa na siku ${daysLeft - 1} • '),
        matcher,
      );
      expect(
        find.text('Ongezea siku za matumizi sasa kabla hujazimiwa huduma'),
        matcher,
      );
      expect(find.text('Fungua chaneli zote'), findsNothing);
    });
  }

  testWidgets('checkout validates input and activates the plan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final state = await AppState.load();
    await tester.pumpWidget(AyomaApp(state: state));
    await pumpPastSplash(tester);

    await switchTab(tester, find.text('Malipo'));
    await tester.tap(find.text('Anza kifurushi'));
    await tester.pumpAndSettle();
    expect(find.text('Lipia sasa'), findsOneWidget);

    final threeMonths = builtIn.plans.last;
    expect(find.textContaining('(siku ${threeMonths.days})'), findsNothing);
    await tester.tap(
      find.text(
        'Kifurushi cha ${builtIn.recommendedPlan.name} (siku ${builtIn.recommendedPlan.days})',
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final threeMonthsOption = find.text(
      'Kifurushi cha ${threeMonths.name} (siku ${threeMonths.days})',
    );
    await tester.ensureVisible(threeMonthsOption);
    await tester.pump();
    await tester.tap(threeMonthsOption);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text(
        'Kifurushi cha ${builtIn.recommendedPlan.name} (siku ${builtIn.recommendedPlan.days})',
      ),
      findsNothing,
    );

    await tester.tap(find.text('Endelea kwa usalama'));
    await tester.pump();
    expect(find.text('Tafadhali andika jina lako kamili.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Ahmed Ali');
    await tester.enterText(find.byType(TextField).at(1), '12345');
    await tester.tap(find.text('Endelea kwa usalama'));
    await tester.pump();
    expect(
      find.text('Namba ya simu ianze na 0 na iwe na tarakimu 10.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).at(1), '0712345678');
    await tester.tap(find.text('Endelea kwa usalama'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Asante, Ahmed'), findsOneWidget);
    expect(state.subscription?.id, threeMonths.id);
    expect(state.daysRemaining, threeMonths.days);

    await tester.tap(find.text('Rudi kwenye chaneli'));
    // The live countdown ticks every frame, so the tree never settles.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('KINATUMIKA'), findsOneWidget);
    expect(find.text('Badilisha au ongeza muda'), findsOneWidget);
    expect(find.text('MILISEKUNDE'), findsOneWidget);
    expect(find.text('89'), findsOneWidget);
  });

  test('activating a plan unlocks premium and extends time', () async {
    final state = await AppState.load();
    final premiumChannel = builtIn.channels.firstWhere((c) => c.premium);

    expect(state.isSubscribed, isFalse);
    expect(state.canWatch(premiumChannel), isFalse);

    await state.activate(builtIn.plans[0]);
    expect(state.isSubscribed, isTrue);
    expect(state.daysRemaining, 7);
    expect(state.canWatch(premiumChannel), isTrue);

    await state.activate(builtIn.plans[1]);
    expect(state.daysRemaining, 37);
    expect(state.subscription?.id, builtIn.plans[1].id);

    final reloaded = await AppState.load();
    expect(reloaded.daysRemaining, 37);
    expect(reloaded.deviceId, state.deviceId);
  });
}
