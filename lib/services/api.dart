import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalog.dart' show Json;

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.code = ''});

  final String message;
  final int status;
  final String code;

  bool get offline => status == 0;

  @override
  String toString() => message;
}

const productionApiUrl = 'https://ayoma-production.up.railway.app';

/// The live API on Railway. For the local API, run with
/// `--dart-define=API_URL=http://10.0.2.2:8080` (Android emulator).
String configuredApiUrl() {
  const fromEnv = String.fromEnvironment('API_URL');
  return fromEnv.isNotEmpty ? fromEnv : productionApiUrl;
}

/// Talks to `/api/v1/app`. Every request after registration carries the
/// device ID and the secret the server issued for it.
class AyomaApi {
  AyomaApi({
    required String baseUrl,
    required this.deviceId,
    required this._prefs,
    this.appVersion = '',
    this.platform = '',
    http.Client? client,
  }) : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
       _http = client ?? http.Client();

  static const _kSecret = 'ayoma.deviceSecret';
  static const _timeout = Duration(seconds: 20);

  final String baseUrl;
  final String deviceId;
  final String appVersion;
  final String platform;
  final SharedPreferences _prefs;
  final http.Client _http;

  String? get _secret => _prefs.getString(_kSecret);

  Future<void> _register() async {
    final res = await _send(
      'POST',
      '/app/register',
      auth: false,
      body: {'deviceId': deviceId, 'platform': platform, 'appVersion': appVersion, 'secret': ?_secret},
    );
    await _prefs.setString(_kSecret, res['secret'] as String);
  }

  Future<Json> _authed(String method, String path, [Object? body]) async {
    // A secret the server rejects (DEVICE_SECRET) is not retried: that would
    // let anyone take over a device ID.
    if (_secret == null) await _register();
    try {
      return await _send(method, path, body: body);
    } on ApiException catch (e) {
      if (e.code != 'DEVICE_UNKNOWN') rethrow;
      // The server lost this device (e.g. deleted by admin): register again.
      await _prefs.remove(_kSecret);
      await _register();
      return _send(method, path, body: body);
    }
  }

  Future<Json> bootstrap() => _authed('GET', '/app/bootstrap');

  Future<void> savePushToken(String token) => _authed('POST', '/app/push-token', {'token': token});

  static const _playbackTtl = Duration(minutes: 3);
  final _playback = <int, ({DateTime at, Future<Json> data})>{};

  /// Cached briefly (including in-flight requests) so a prefetch on touch, or
  /// reopening a channel, starts the stream without another round trip.
  Future<Json> playback(int channelId, {bool fresh = false}) {
    final hit = _playback[channelId];
    if (!fresh && hit != null && DateTime.now().difference(hit.at) < _playbackTtl) return hit.data;
    final data = _authed('GET', '/app/channels/$channelId/playback').then((res) => res['playback'] as Json);
    final entry = (at: DateTime.now(), data: data);
    _playback[channelId] = entry;
    data.catchError((Object _) {
      if (identical(_playback[channelId], entry)) _playback.remove(channelId);
      return <String, dynamic>{};
    });
    return data;
  }

  Future<Json> startPayment({required String planId, required String name, required String phone}) async =>
      (await _authed('POST', '/app/payments', {'planId': planId, 'name': name, 'phone': phone}))['payment']
          as Json;

  /// Returns `{payment, user}`; the server re-checks the provider each call.
  Future<Json> paymentStatus(int paymentId) => _authed('GET', '/app/payments/$paymentId');

  Future<Json> _send(String method, String path, {Object? body, bool auth = true}) async {
    final request = http.Request(method, Uri.parse('$baseUrl/api/v1$path'))
      ..headers.addAll({
        'Accept': 'application/json',
        'X-App-Version': appVersion,
        'X-Platform': platform,
        if (auth) 'X-Device-Id': deviceId,
        if (auth && _secret != null) 'X-Device-Secret': _secret!,
      });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(request).timeout(_timeout));
    } catch (_) {
      throw ApiException('Hakuna mtandao. Angalia bando lako kisha ujaribu tena.');
    }

    Json json;
    try {
      final decoded = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
      json = decoded is Json ? decoded : {};
    } catch (_) {
      json = {};
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    throw ApiException(
      '${json['error'] ?? 'Hitilafu ya seva (${res.statusCode}). Jaribu tena.'}',
      status: res.statusCode,
      code: '${json['code'] ?? ''}',
    );
  }
}
