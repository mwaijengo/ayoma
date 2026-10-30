import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalog.dart';
import '../services/api.dart';

enum VideoQuality {
  auto('Auto', 'AUTO', 0),
  p360('360p', '360p', 360),
  p480('480p', '480p', 480),
  p720('720p', '720p HD', 720),
  p1080('1080p', '1080p FHD', 1080);

  static const fallback = VideoQuality.p360;

  const VideoQuality(this.label, this.badge, this.maxHeight);

  final String label;
  final String badge;

  /// Highest video height the player may pick; 0 means no cap.
  final int maxHeight;
}

/// Switches the admin controls from the server's `config` block.
class RemoteConfig {
  const RemoteConfig({
    this.maintenance = false,
    this.maintenanceMessage = '',
    this.latestVersion = '',
    this.minVersion = '',
    this.forceUpdate = false,
    this.updateMessage = '',
    this.updateUrl = '',
    this.supportWhatsApp = supportWhatsAppNumber,
    this.refreshToken = 0,
  });

  factory RemoteConfig.fromJson(Json j) {
    final m = (j['maintenance'] as Map?) ?? const {};
    final u = (j['update'] as Map?) ?? const {};
    final whatsapp = '${j['supportWhatsApp'] ?? ''}';
    return RemoteConfig(
      maintenance: m['enabled'] == true,
      maintenanceMessage: '${m['message'] ?? ''}',
      latestVersion: '${u['latestVersion'] ?? ''}',
      minVersion: '${u['minVersion'] ?? ''}',
      forceUpdate: u['force'] == true,
      updateMessage: '${u['message'] ?? ''}',
      updateUrl: '${u['url'] ?? ''}',
      supportWhatsApp: whatsapp.isEmpty ? supportWhatsAppNumber : whatsapp,
      refreshToken: (j['refreshToken'] as num?)?.toInt() ?? 0,
    );
  }

  final bool maintenance;
  final String maintenanceMessage;
  final String latestVersion;
  final String minVersion;
  final bool forceUpdate;
  final String updateMessage;
  final String updateUrl;
  final String supportWhatsApp;
  final int refreshToken;
}

/// Compares dotted versions ("1.2.0" < "1.10.0"); missing parts count as 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.split(RegExp(r'[.+]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();
  final x = parts(a);
  final y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

class AppState extends ChangeNotifier {
  AppState._(this._prefs, {this.api, this.appVersion = '1.0.0'})
    : deviceId = _prefs.getString(_kDeviceId) ?? _makeDeviceId(),
      _planId = _prefs.getString(_kPlanId),
      _expiresAt = _readDate(_prefs.getInt(_kExpiresAt)),
      _periodDays = _prefs.getInt(_kPeriodDays) ?? 0,
      _notifications = _prefs.getBool(_kNotifications) ?? true,
      _dataSaver = _prefs.getBool(_kDataSaver) ?? false,
      _quality =
          VideoQuality.values.asNameMap()[_prefs.getString(_kQuality)] ??
          VideoQuality.fallback,
      _startMuted = _prefs.getBool(_kStartMuted) ?? false,
      _autoLandscape = _prefs.getBool(_kAutoLandscape) ?? false,
      _autoHideControls = _prefs.getBool(_kAutoHideControls) ?? true,
      _blocked = _prefs.getBool(_kBlocked) ?? false,
      subscriberName = _prefs.getString(_kSubscriberName) {
    _prefs.setString(_kDeviceId, deviceId);
    _restoreCachedBootstrap();
  }

  static const _kDeviceId = 'ayoma.deviceId';
  static const _kPlanId = 'ayoma.planId';
  static const _kExpiresAt = 'ayoma.expiresAt';
  static const _kPeriodDays = 'ayoma.periodDays';
  static const _kNotifications = 'ayoma.notifications';
  static const _kDataSaver = 'ayoma.dataSaver';
  static const _kSubscriberName = 'ayoma.subscriberName';
  static const _kSubscriberPhone = 'ayoma.subscriberPhone';
  static const _kQuality = 'ayoma.player.quality';
  static const _kStartMuted = 'ayoma.player.startMuted';
  static const _kAutoLandscape = 'ayoma.player.autoLandscape';
  static const _kAutoHideControls = 'ayoma.player.autoHideControls';
  static const _kBlocked = 'ayoma.blocked';
  static const _kBootstrap = 'ayoma.bootstrap';
  static const _kRefreshToken = 'ayoma.refreshToken';

  /// Loads saved state. Pass [api] to sync with the server; without it the
  /// app runs on the built-in catalog (tests, or no server configured).
  static Future<AppState> load({
    AyomaApi Function(SharedPreferences prefs, String deviceId)? api,
    String appVersion = '1.0.0',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(_kDeviceId) ?? _makeDeviceId();
    await prefs.setString(_kDeviceId, deviceId);
    return AppState._(prefs, api: api?.call(prefs, deviceId), appVersion: appVersion);
  }

  final SharedPreferences _prefs;
  final AyomaApi? api;
  final String appVersion;
  final String deviceId;
  String? subscriberName;

  String? get subscriberPhone => _prefs.getString(_kSubscriberPhone);

  /// With a server, channels and banners only ever come from it, so content an
  /// admin deleted can never show up, not even offline on a first launch.
  late Catalog _catalog = api == null
      ? Catalog.builtIn
      : Catalog(plans: Catalog.builtIn.plans, channels: const [], slides: const []);
  RemoteConfig _config = const RemoteConfig();
  bool _blocked;
  bool _restartRequested = false;
  DateTime? _lastSync;
  Future<void>? _syncing;
  Timer? _autoSync;

  String? _planId;
  DateTime? _expiresAt;
  int _periodDays;
  bool _notifications;
  bool _dataSaver;
  VideoQuality _quality;
  bool _startMuted;
  bool _autoLandscape;
  bool _autoHideControls;

  Catalog get catalog => _catalog;
  RemoteConfig get config => _config;
  bool get online => api != null;
  bool get blocked => _blocked;

  /// Set when the admin pressed "Refresh apps"; the UI restarts and clears it.
  bool get restartRequested => _restartRequested;

  bool get updateRequired =>
      _config.forceUpdate &&
      _config.minVersion.isNotEmpty &&
      compareVersions(appVersion, _config.minVersion) < 0;

  bool get updateAvailable =>
      _config.latestVersion.isNotEmpty && compareVersions(appVersion, _config.latestVersion) < 0;

  bool get notifications => _notifications;
  bool get dataSaver => _dataSaver;
  VideoQuality get quality => _quality;
  bool get startMuted => _startMuted;
  bool get autoLandscape => _autoLandscape;
  bool get autoHideControls => _autoHideControls;

  /// Quality actually used for playback; "auto" drops to SD on data saver.
  VideoQuality get effectiveQuality => _quality == VideoQuality.auto
      ? (_dataSaver ? VideoQuality.p360 : VideoQuality.p720)
      : _quality;

  bool get isSubscribed =>
      _expiresAt != null && _expiresAt!.isAfter(DateTime.now());

  Plan? get subscription {
    if (!isSubscribed) return null;
    return _catalog.planById(_planId) ??
        Plan(
          id: _planId ?? 'custom',
          name: 'Kifurushi',
          days: _periodDays,
          priceTzs: 0,
          quality: 'HD',
          description: 'Kifurushi maalum',
        );
  }

  DateTime? get expiresAt => isSubscribed ? _expiresAt : null;

  Duration get timeRemaining {
    if (!isSubscribed) return Duration.zero;
    return _expiresAt!.difference(DateTime.now());
  }

  int get daysRemaining => (timeRemaining.inHours / 24).ceil();

  /// Fraction of the current paid period still left, from 0 to 1.
  double get remainingFraction => fractionFor(timeRemaining);

  double fractionFor(Duration remaining) {
    if (_periodDays <= 0) return 0;
    final period = Duration(days: _periodDays).inMilliseconds;
    return (remaining.inMilliseconds / period).clamp(0.0, 1.0);
  }

  /// Rebuilds listeners once the subscription has run out.
  void checkExpiry() {
    if (_expiresAt != null && !isSubscribed) notifyListeners();
  }

  bool canWatch(Channel channel) => !channel.premium || isSubscribed;

  /// Starts fetching stream details as soon as a finger touches a channel.
  void prefetchPlayback(Channel channel) {
    final id = channel.id;
    if (api == null || id == null || !canWatch(channel)) return;
    api!.playback(id).ignore();
  }

  // ───────────────────────── Server sync ─────────────────────────

  /// Fetches catalog, subscription and admin config. Calls within [minGap]
  /// of the last success are skipped unless [force] is set.
  Future<void> sync({bool force = false, Duration minGap = const Duration(seconds: 20)}) {
    if (api == null) return Future.value();
    final last = _lastSync;
    if (!force && last != null && DateTime.now().difference(last) < minGap) return Future.value();
    return _syncing ??= _doSync().whenComplete(() => _syncing = null);
  }

  Future<void> _doSync() async {
    try {
      final res = await api!.bootstrap();
      _applyBootstrap(res, fromCache: false);
      _lastSync = DateTime.now();
      await _prefs.setString(_kBootstrap, jsonEncode(res));
    } on ApiException catch (e) {
      debugPrint('AyomaMax sync failed: ${e.message}');
    }
  }

  void startAutoSync({Duration every = const Duration(seconds: 60)}) {
    _autoSync?.cancel();
    if (api == null) return;
    _autoSync = Timer.periodic(every, (_) => sync());
  }

  void _restoreCachedBootstrap() {
    final raw = _prefs.getString(_kBootstrap);
    if (raw == null || api == null) return;
    try {
      _applyBootstrap(jsonDecode(raw) as Json, fromCache: true);
    } catch (_) {
      _prefs.remove(_kBootstrap);
    }
  }

  /// True once channels and carousel came from the server (live or cached).
  bool get hasServerCatalog => _hasServerCatalog;
  bool _hasServerCatalog = false;

  /// On a first launch, waits up to [timeout] for the server catalog so the
  /// home screen does not start empty.
  Future<void> waitForCatalog({Duration timeout = const Duration(seconds: 7)}) {
    if (api == null || _hasServerCatalog) return Future.value();
    return sync(force: true).timeout(timeout, onTimeout: () {});
  }

  void _applyBootstrap(Json res, {required bool fromCache}) {
    final server = Catalog.fromJson(res);
    // Plans must never be empty: the payment screens need a recommended plan.
    _catalog = Catalog(
      plans: server.plans.isNotEmpty ? server.plans : _catalog.plans,
      channels: server.channels,
      slides: server.slides,
    );
    _hasServerCatalog = true;
    if (!fromCache) api?.keepPlaybackFor({for (final c in server.channels) ?c.id});
    _config = RemoteConfig.fromJson((res['config'] as Map?)?.cast<String, dynamic>() ?? const {});
    if (!fromCache && res['user'] is Map) applyServerUser((res['user'] as Map).cast<String, dynamic>());

    final seen = _prefs.getInt(_kRefreshToken);
    if (_config.refreshToken != 0 && seen != _config.refreshToken) {
      _prefs.setInt(_kRefreshToken, _config.refreshToken);
      if (seen != null && !fromCache) _restartRequested = true;
    }
    notifyListeners();
  }

  void acknowledgeRestart() => _restartRequested = false;

  /// Requests a UI restart, e.g. from a "refresh" push message.
  void requestRestart() {
    _restartRequested = true;
    notifyListeners();
  }

  /// The server is the source of truth for the package once connected.
  void applyServerUser(Json user) {
    _planId = user['planId'] as String?;
    _expiresAt = user['expiresAt'] == null ? null : DateTime.tryParse('${user['expiresAt']}')?.toLocal();
    _periodDays = (user['periodDays'] as num?)?.toInt() ?? 0;
    _blocked = user['blocked'] == true;
    final name = '${user['name'] ?? ''}';
    if (name.isNotEmpty) subscriberName = name;
    notifyListeners();

    _planId == null ? _prefs.remove(_kPlanId) : _prefs.setString(_kPlanId, _planId!);
    _expiresAt == null
        ? _prefs.remove(_kExpiresAt)
        : _prefs.setInt(_kExpiresAt, _expiresAt!.millisecondsSinceEpoch);
    _prefs.setInt(_kPeriodDays, _periodDays);
    _prefs.setBool(_kBlocked, _blocked);
    if (name.isNotEmpty) _prefs.setString(_kSubscriberName, name);
  }

  Future<void> rememberPayer({required String name, required String phone}) async {
    subscriberName = name;
    await _prefs.setString(_kSubscriberName, name);
    await _prefs.setString(_kSubscriberPhone, phone);
  }

  /// Local activation, used only when no server is configured.
  Future<void> activate(Plan plan, {String? name, String? phone}) async {
    final now = DateTime.now();
    final base = isSubscribed ? _expiresAt! : now;
    _expiresAt = base.add(Duration(days: plan.days));
    _periodDays = (_expiresAt!.difference(now).inHours / 24).ceil();
    _planId = plan.id;
    if (name != null) subscriberName = name;
    notifyListeners();

    await _prefs.setString(_kPlanId, plan.id);
    await _prefs.setInt(_kExpiresAt, _expiresAt!.millisecondsSinceEpoch);
    await _prefs.setInt(_kPeriodDays, _periodDays);
    if (name != null) await _prefs.setString(_kSubscriberName, name);
    if (phone != null) await _prefs.setString(_kSubscriberPhone, phone);
  }

  Future<void> setNotifications(bool value) async {
    _notifications = value;
    notifyListeners();
    await _prefs.setBool(_kNotifications, value);
  }

  Future<void> setDataSaver(bool value) async {
    _dataSaver = value;
    notifyListeners();
    await _prefs.setBool(_kDataSaver, value);
  }

  Future<void> setQuality(VideoQuality value) async {
    _quality = value;
    notifyListeners();
    await _prefs.setString(_kQuality, value.name);
  }

  Future<void> setStartMuted(bool value) async {
    _startMuted = value;
    notifyListeners();
    await _prefs.setBool(_kStartMuted, value);
  }

  Future<void> setAutoLandscape(bool value) async {
    _autoLandscape = value;
    notifyListeners();
    await _prefs.setBool(_kAutoLandscape, value);
  }

  Future<void> setAutoHideControls(bool value) async {
    _autoHideControls = value;
    notifyListeners();
    await _prefs.setBool(_kAutoHideControls, value);
  }

  @override
  void dispose() {
    _autoSync?.cancel();
    super.dispose();
  }

  static DateTime? _readDate(int? millis) =>
      millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);

  static String _makeDeviceId() {
    final random = Random.secure();
    String part() => random.nextInt(0xFFFFFFFF).toRadixString(36).toUpperCase();
    return 'AN-${part()}-${part()}';
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()?.notifier;
}
