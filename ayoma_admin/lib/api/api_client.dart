import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.code = ''});

  final String message;
  final int status;
  final String code;

  bool get unauthorized => status == 401;

  @override
  String toString() => message;
}

const productionServerUrl = 'https://ayoma-production.up.railway.app';

/// The live API on Railway. For the local API, run with
/// `--dart-define=API_URL=http://10.0.2.2:8080` (Android emulator).
String defaultServerUrl() {
  const fromEnv = String.fromEnvironment('API_URL');
  return fromEnv.isNotEmpty ? fromEnv : productionServerUrl;
}

String normalizeServerUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return defaultServerUrl();
  if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.endsWith('/api/v1')) url = url.substring(0, url.length - 7);
  return url;
}

class ApiClient {
  ApiClient({required this.baseUrl, this.token, http.Client? client, this.onUnauthorized})
    : _http = client ?? http.Client();

  String baseUrl;
  String? token;
  final http.Client _http;

  /// Called when the server rejects the admin token (expired or revoked).
  VoidCallback? onUnauthorized;

  static const _timeout = Duration(seconds: 25);

  Uri _uri(String path, [Map<String, Object?>? query]) {
    final q = <String, String>{
      for (final e in (query ?? const {}).entries)
        if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}',
    };
    return Uri.parse('$baseUrl/api/v1$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> get(String path, [Map<String, Object?>? query]) =>
      _send(() => _http.get(_uri(path, query), headers: _headers));

  Future<Map<String, dynamic>> post(String path, [Object? body]) => _send(
    () => _http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? const {})),
  );

  Future<Map<String, dynamic>> put(String path, Object body) =>
      _send(() => _http.put(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<Map<String, dynamic>> patch(String path, Object body) =>
      _send(() => _http.patch(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<Map<String, dynamic>> delete(String path) =>
      _send(() => _http.delete(_uri(path), headers: _headers));

  /// Uploads raw bytes (e.g. an image) with the given content type.
  Future<Map<String, dynamic>> postBytes(String path, List<int> bytes, String contentType) => _send(
    () => _http.post(_uri(path), headers: {..._headers, 'Content-Type': contentType}, body: bytes),
  );

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    http.Response res;
    try {
      res = await request().timeout(_timeout);
    } on TimeoutException {
      throw ApiException('The server took too long to respond.');
    } catch (_) {
      throw ApiException('Cannot reach the server at $baseUrl.');
    }

    Map<String, dynamic> body;
    try {
      final decoded = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
      body = decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    } catch (_) {
      body = {};
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return body;

    final error = ApiException(
      _errorMessage(body) ?? 'Request failed (${res.statusCode}).',
      status: res.statusCode,
      code: '${body['code'] ?? ''}',
    );
    if (error.unauthorized && token != null) onUnauthorized?.call();
    throw error;
  }

  String? _errorMessage(Map<String, dynamic> body) {
    final error = body['error'] ?? body['message'];
    return error == null ? null : '$error';
  }
}
