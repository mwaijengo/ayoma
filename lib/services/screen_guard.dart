import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Blocks screenshots and screen recording (Android FLAG_SECURE).
/// The app starts secure; only the Settings tab turns it off.
class ScreenGuard {
  ScreenGuard._();

  static const _channel = MethodChannel('ayoma/screen');
  static bool _secure = true;

  /// Store screenshot builds only: `--dart-define=AYOMA_ALLOW_CAPTURE=true`.
  static const _allowCapture = bool.fromEnvironment('AYOMA_ALLOW_CAPTURE');

  static bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> setSecure(bool secure) async {
    if (_allowCapture) secure = false;
    if (!_supported || secure == _secure) return;
    _secure = secure;
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on PlatformException catch (_) {
      _secure = !secure;
    } on MissingPluginException catch (_) {
      _secure = !secure;
    }
  }
}
