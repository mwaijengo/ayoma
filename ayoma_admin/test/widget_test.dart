import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ayoma_admin/api/api_client.dart';
import 'package:ayoma_admin/main.dart';
import 'package:ayoma_admin/screens/channel_form.dart';
import 'package:ayoma_admin/state/session.dart';

const _dashboard = {
  'ok': true,
  'stats': {
    'revenueToday': 17000,
    'paymentsToday': 3,
    'revenueMonth': 120000,
    'revenueTotal': 450000,
    'paymentsPending': 1,
    'usersTotal': 240,
    'usersToday': 12,
    'premiumActive': 58,
    'expiringSoon': 7,
    'expired': 31,
    'onlineNow': 19,
    'channelsActive': 6,
  },
  'last7Days': [
    {'day': '2026-10-16', 'revenue': 5000},
    {'day': '2026-10-17', 'revenue': 0},
    {'day': '2026-10-18', 'revenue': 12000},
    {'day': '2026-10-19', 'revenue': 7000},
    {'day': '2026-10-20', 'revenue': 2000},
    {'day': '2026-10-21', 'revenue': 9000},
    {'day': '2026-10-22', 'revenue': 17000},
  ],
  'recentPayments': [],
};

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

MockClient _server({List<http.Request>? log}) => MockClient((req) async {
  log?.add(req);
  final path = req.url.path;
  if (path.endsWith('/auth/admin-login')) {
    final password = (jsonDecode(req.body) as Map)['password'];
    if (password != 'siri-kubwa') return _json({'ok': false, 'error': 'Wrong password'}, 401);
    return _json({
      'ok': true,
      'token': 'tok',
      'expiresAt': DateTime.now().add(const Duration(hours: 24)).toUtc().toIso8601String(),
    });
  }
  if (req.headers['Authorization'] != 'Bearer tok') {
    return _json({'ok': false, 'error': 'Session expired. Log in again.'}, 401);
  }
  if (path.endsWith('/admin/dashboard')) return _json(_dashboard);
  return _json({'ok': false, 'error': 'Not found'}, 404);
});

Future<void> _pumpApp(WidgetTester tester, Session session) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AdminApp(session: session));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('password login opens the dashboard with today\'s revenue', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final session = Session(
      prefs: prefs,
      client: ApiClient(baseUrl: 'http://test', client: _server()),
    );
    await _pumpApp(tester, session);

    expect(find.text('Log in'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'wrong');
    await tester.pump();
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong password'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'siri-kubwa');
    await tester.pump();
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('TSh 17,000'), findsOneWidget);
    expect(find.text('3 payments today'), findsOneWidget);
    expect(prefs.getString('ayoma.admin.token'), 'tok');

    // Server-side expiry (401) sends the admin back to the login screen.
    session.client.token = 'old';
    await session.client.get('/admin/dashboard').catchError((_) => <String, dynamic>{});
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget);
    expect(find.textContaining('expired after 24 hours'), findsOneWidget);
    expect(prefs.getString('ayoma.admin.token'), isNull);
  });

  testWidgets('a stored session older than 24 hours asks for the password again', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ayoma.admin.token': 'tok',
      'ayoma.admin.expiresAt': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
    });
    final session = Session(
      prefs: await SharedPreferences.getInstance(),
      client: ApiClient(baseUrl: 'http://test', client: _server()),
    );
    expect(session.loggedIn, isFalse);
    await _pumpApp(tester, session);
    expect(find.textContaining('expired after 24 hours'), findsOneWidget);
  });

  testWidgets('a valid stored session skips the login screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ayoma.admin.token': 'tok',
      'ayoma.admin.expiresAt': DateTime.now().add(const Duration(hours: 5)).toIso8601String(),
    });
    final session = Session(
      prefs: await SharedPreferences.getInstance(),
      client: ApiClient(baseUrl: 'http://test', client: _server()),
    );
    await _pumpApp(tester, session);
    expect(find.text('TSh 17,000'), findsOneWidget);
    session.dispose();
  });

  test('header lines and ClearKey validation', () {
    expect(parseHeaderLines('Referer: https://a.com/\nX-Token:  abc \nbad line'), {
      'Referer': 'https://a.com/',
      'X-Token': 'abc',
    });
    expect(validateClearKeys('feedf00deedeadbeeff0baadf00dd00d:00112233445566778899aabbccddeeff'), isNull);
    expect(validateClearKeys('abc:def'), isNotNull);
    expect(validateClearKeys('only-one-part'), isNotNull);
  });

  test('server URL normalisation', () {
    expect(normalizeServerUrl('api.example.com/'), 'https://api.example.com');
    expect(normalizeServerUrl('http://10.0.2.2:8080/api/v1/'), 'http://10.0.2.2:8080');
  });
}
