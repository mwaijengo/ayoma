import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../state/app_state.dart';

/// Firebase Cloud Messaging for admin notifications, renewal reminders and
/// "refresh apps".
///
/// Defaults to the `uhurumax-ceaf2` project (values from google-services.json,
/// which are public client identifiers). Each can be overridden with a
/// `--dart-define`: FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_SENDER_ID,
/// FIREBASE_PROJECT_ID.
class PushService {
  PushService._(this._state);

  static const _apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyDKWtU7FUfKoGERt8cokOpxO-5HvPWVPuc',
  );
  static const _appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:270201140107:android:88eaf4966577e913c6758e',
  );
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '270201140107');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'uhurumax-ceaf2');

  /// Must match the channel created in MainActivity and sent by the server.
  static const _channel = AndroidNotificationDetails(
    'uhurumax_alerts',
    'Taarifa za AyomaMax',
    channelDescription: 'Vifurushi, mechi na taarifa muhimu',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_stat_ayoma',
  );

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final AppState _state;
  final _local = FlutterLocalNotificationsPlugin();
  bool? _registeredFor;
  DateTime _savedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _queue = Future.value();

  /// Starts push when the app is connected to the server.
  static Future<PushService?> start(AppState state) async {
    if (!supported || state.api == null) return null;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _senderId,
          projectId: _projectId,
        ),
      );
      final service = PushService._(state);
      await service._init();
      return service;
    } catch (e) {
      debugPrint('AyomaMax push disabled: $e');
      return null;
    }
  }

  Future<void> _init() async {
    await _local.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_ayoma')),
      onDidReceiveNotificationResponse: (_) => _state.sync(force: true),
    );

    final messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_onData);
    final initial = await messaging.getInitialMessage();
    if (initial != null) _onData(initial);
    messaging.onTokenRefresh.listen((_) {
      _registeredFor = null;
      _sync();
    });
    _state.addListener(_sync);
    AppLifecycleListener(onResume: _refreshIfStale);
    await _sync();
  }

  /// Re-registers the token now and then so the server never keeps a stale
  /// one for phones that stay in the background for days.
  void _refreshIfStale() {
    if (DateTime.now().difference(_savedAt) < const Duration(hours: 6)) return;
    _registeredFor = null;
    _sync();
  }

  /// Android only draws notifications itself while the app is in the
  /// background, so show them here when the app is open.
  void _onForeground(RemoteMessage message) {
    final n = message.notification;
    if (n != null && _state.notifications) {
      _local.show(
        id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: n.title,
        body: n.body,
        notificationDetails: const NotificationDetails(android: _channel),
      );
    }
    _onData(message);
  }

  void _onData(RemoteMessage message) {
    if (message.data['type'] == 'refresh') {
      _state.requestRestart();
    } else {
      _state.sync(force: true);
    }
  }

  /// Runs one sync at a time; Android rejects overlapping permission requests.
  Future<void> _sync() => _queue = _queue.then((_) => _syncNow());

  /// Sends the token while notifications are on, and clears it when off.
  Future<void> _syncNow() async {
    final wanted = _state.notifications;
    if (_registeredFor == wanted) return;
    _registeredFor = wanted;
    try {
      String token = '';
      if (wanted) {
        final settings = await FirebaseMessaging.instance.requestPermission();
        if (settings.authorizationStatus != AuthorizationStatus.denied) {
          token = await FirebaseMessaging.instance.getToken() ?? '';
        }
      }
      await _state.api!.savePushToken(token);
      _savedAt = DateTime.now();
    } catch (e) {
      _registeredFor = null;
      debugPrint('AyomaMax push token not saved: $e');
    }
  }
}
