import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ayoma/main.dart';
import 'package:ayoma/screens/splash_screen.dart';
import 'package:ayoma/services/api.dart';
import 'package:ayoma/state/app_state.dart';

/// In-memory stand-in for `/api/v1/app`.
class FakeServer {
  final requests = <String>[];
  final knownDevices = <String, String>{};
  Map<String, dynamic> user = {'planId': null, 'expiresAt': null, 'periodDays': 0, 'blocked': false};
  Map<String, dynamic> maintenance = {'enabled': false, 'message': ''};
  Map<String, dynamic> update = {'latestVersion': '1.0.0', 'minVersion': '1.0.0', 'force': false};
  int refreshToken = 1;
  String paymentStatus = 'pending';

  static const plans = [
    {'id': 'weekly', 'name': 'Wiki 1', 'days': 7, 'priceTzs': 2500, 'quality': 'HD', 'description': 'Chaneli zote'},
    {
      'id': 'premium',
      'name': 'Mwezi 1',
      'days': 30,
      'priceTzs': 6000,
      'quality': 'HD',
      'description': 'Chaneli zote',
      'recommended': true,
    },
  ];

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path.replaceFirst('/api/v1', '');
    requests.add('${req.method} $path');
    if (path == '/app/register') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      knownDevices[body['deviceId'] as String] = 'secret-1';
      return _json({'secret': 'secret-1'});
    }
    final device = req.headers['X-Device-Id'] ?? req.headers['x-device-id'];
    if (!knownDevices.containsKey(device)) {
      return _json({'error': 'Unknown device', 'code': 'DEVICE_UNKNOWN'}, 401);
    }
    switch (path) {
      case '/app/bootstrap':
        return _json({
          'serverTime': DateTime.now().toUtc().toIso8601String(),
          'user': user,
          'plans': plans,
          'channels': [
            {'id': 1, 'name': 'Ayoma Sports 1', 'category': 'Mpira', 'image': '', 'premium': true, 'viewers': '2.1K'},
            {'id': 2, 'name': 'Ayoma Habari', 'category': 'Habari', 'image': '', 'premium': false, 'viewers': ''},
          ],
          'slides': <Object>[],
          'config': {
            'maintenance': maintenance,
            'update': update,
            'supportWhatsApp': '255711111111',
            'refreshToken': refreshToken,
          },
        });
      case '/app/payments':
        return _json({'payment': _payment});
      case '/app/payments/7':
        if (paymentStatus == 'paid') {
          user = {
            'planId': 'premium',
            'expiresAt': DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String(),
            'periodDays': 30,
            'blocked': false,
          };
        }
        return _json({'payment': _payment, 'user': user});
    }
    return _json({'error': 'Not found'}, 404);
  }

  Map<String, dynamic> get _payment => {'id': 7, 'planId': 'premium', 'status': paymentStatus};

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}

Future<AppState> loadOnline(FakeServer server, {String appVersion = '1.0.0'}) async {
  final state = await AppState.load(
    appVersion: appVersion,
    api: (prefs, deviceId) => AyomaApi(
      baseUrl: 'http://api.test',
      deviceId: deviceId,
      prefs: prefs,
      client: MockClient(server.handle),
    ),
  );
  await state.sync(force: true);
  return state;
}

Future<void> pumpApp(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AyomaApp(state: state));
  await tester.pump(SplashGate.duration);
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('uses the channels and packages from the server', (tester) async {
    final server = FakeServer();
    final state = await loadOnline(server);
    expect(server.requests.take(2), ['POST /app/register', 'GET /app/bootstrap']);
    expect(state.catalog.channels.map((c) => c.name), ['Ayoma Sports 1', 'Ayoma Habari']);
    expect(state.catalog.recommendedPlan.priceTzs, 6000);
    expect(state.config.supportWhatsApp, '255711111111');

    await pumpApp(tester, state);
    await tester.tap(find.text('Ona zote'));
    await tester.pump();
    await tester.pump(SplashGate.duration);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Chaneli zote (2)'), findsOneWidget);
    expect(find.text('Ayoma Sports 1'), findsOneWidget);
    state.dispose();
  });

  testWidgets('maintenance mode covers the app until it is switched off', (tester) async {
    final server = FakeServer()..maintenance = {'enabled': true, 'message': 'Tunarudi saa 2 usiku'};
    final state = await loadOnline(server);
    await pumpApp(tester, state);
    expect(find.text('Tunaboresha huduma'), findsOneWidget);
    expect(find.text('Tunarudi saa 2 usiku'), findsOneWidget);

    server.maintenance = {'enabled': false, 'message': ''};
    await tester.tap(find.text('Jaribu tena'));
    await tester.pump();
    await tester.pump(SplashGate.duration);
    expect(find.text('Tunaboresha huduma'), findsNothing);
    state.dispose();
  });

  testWidgets('must-update blocks old versions only', (tester) async {
    final server = FakeServer()
      ..update = {'latestVersion': '1.3.0', 'minVersion': '1.2.0', 'force': true, 'message': ''};
    final old = await loadOnline(server, appVersion: '1.1.9');
    expect(old.updateRequired, isTrue);
    await pumpApp(tester, old);
    expect(find.text('Kuna toleo jipya'), findsOneWidget);
    old.dispose();

    SharedPreferences.setMockInitialValues({});
    final current = await loadOnline(server, appVersion: '1.2.0');
    expect(current.updateRequired, isFalse);
    expect(current.updateAvailable, isTrue);
    current.dispose();
  });

  testWidgets('blocked devices see the blocked screen', (tester) async {
    final server = FakeServer()..user = {...FakeServer().user, 'blocked': true};
    final state = await loadOnline(server);
    await pumpApp(tester, state);
    expect(find.text('Akaunti imezuiwa'), findsOneWidget);
    state.dispose();
  });

  testWidgets('"refresh apps" from the admin restarts the app', (tester) async {
    final server = FakeServer();
    final state = await loadOnline(server);
    await pumpApp(tester, state);
    expect(find.byType(SplashScreen), findsNothing);

    server.refreshToken = 2;
    await state.sync(force: true);
    await tester.pump();
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(state.restartRequested, isFalse);
    await tester.pump(SplashGate.duration);
    state.dispose();
  });

  testWidgets('checkout waits for the PIN, then activates from the server', (tester) async {
    final server = FakeServer();
    final state = await loadOnline(server);
    await pumpApp(tester, state);

    await tester.tap(find.text('Malipo'));
    await tester.pump();
    await tester.pump(SplashGate.duration);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Anza kifurushi'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Ahmed Ali');
    await tester.enterText(find.byType(TextField).at(1), '0712345678');
    await tester.tap(find.text('Endelea kwa usalama'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Weka PIN kwenye simu yako'), findsOneWidget);
    expect(server.requests, contains('POST /app/payments'));
    expect(state.isSubscribed, isFalse);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Weka PIN kwenye simu yako'), findsOneWidget);

    server.paymentStatus = 'paid';
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Asante, Ahmed'), findsOneWidget);
    expect(state.isSubscribed, isTrue);
    expect(state.subscription?.id, 'premium');
    state.dispose();
  });

  test('a device the server forgot registers again', () async {
    final server = FakeServer();
    final state = await loadOnline(server);
    server.knownDevices.clear();
    await state.sync(force: true);
    expect(server.requests.where((r) => r == 'POST /app/register').length, 2);
    expect(state.catalog.channels.length, 2);
  });
}
