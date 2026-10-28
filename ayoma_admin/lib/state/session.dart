import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/admin_api.dart';
import '../api/api_client.dart';

/// Admin login state. A session always ends 24 hours after login (the server
/// token carries the same expiry), after which the password is asked again.
class Session extends ChangeNotifier {
  Session({required SharedPreferences prefs, ApiClient? client})
    // ignore: prefer_initializing_formals
    : _prefs = prefs,
      client = client ?? ApiClient(baseUrl: defaultServerUrl()) {
    this.client.onUnauthorized = () => _end(expired: true);
    // Older builds saved a server address (often the local one); always use the built-in one now.
    if (_prefs.containsKey(_kServer)) {
      _prefs.remove(_kServer);
      _clearStored();
    }
    final token = _prefs.getString(_kToken);
    final expires = DateTime.tryParse(_prefs.getString(_kExpires) ?? '');
    if (token != null && expires != null && expires.isAfter(DateTime.now())) {
      _expiresAt = expires;
      this.client.token = token;
      _scheduleExpiry();
    } else if (token != null) {
      _clearStored();
      _expiredNotice = true;
    }
    api = AdminApi(this.client);
  }

  static const _kToken = 'ayoma.admin.token';
  static const _kExpires = 'ayoma.admin.expiresAt';
  static const _kServer = 'ayoma.admin.server';

  final SharedPreferences _prefs;
  final ApiClient client;
  late final AdminApi api;

  DateTime? _expiresAt;
  Timer? _expiryTimer;
  bool _expiredNotice = false;

  bool get loggedIn => client.token != null && _expiresAt != null;
  DateTime? get expiresAt => _expiresAt;
  String get serverUrl => client.baseUrl;

  /// True once after the session timed out, so the login screen can say why.
  bool consumeExpiredNotice() {
    final value = _expiredNotice;
    _expiredNotice = false;
    return value;
  }

  Future<void> login(String password) async {
    final res = await client.post('/auth/admin-login', {'password': password});
    final token = res['token'] as String;
    final expires =
        DateTime.tryParse('${res['expiresAt']}')?.toLocal() ??
        DateTime.now().add(const Duration(hours: 24));
    client.token = token;
    _expiresAt = expires;
    await _prefs.setString(_kToken, token);
    await _prefs.setString(_kExpires, expires.toIso8601String());
    _scheduleExpiry();
    notifyListeners();
  }

  void logout() => _end(expired: false);

  void _end({required bool expired}) {
    if (!loggedIn) return;
    _expiryTimer?.cancel();
    client.token = null;
    _expiresAt = null;
    _expiredNotice = expired;
    _clearStored();
    notifyListeners();
  }

  void _clearStored() {
    _prefs.remove(_kToken);
    _prefs.remove(_kExpires);
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final left = _expiresAt!.difference(DateTime.now());
    _expiryTimer = Timer(left.isNegative ? Duration.zero : left, () => _end(expired: true));
  }

  /// Timers pause while the app is in the background, so re-check on resume.
  void checkExpiry() {
    if (_expiresAt != null && !_expiresAt!.isAfter(DateTime.now())) _end(expired: true);
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}

class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({super.key, required Session session, required super.child})
    : super(notifier: session);

  static Session of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  static Session read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}
