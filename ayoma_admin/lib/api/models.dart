typedef Json = Map<String, dynamic>;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _str(Object? v) => v == null ? '' : '$v';
Map<String, String> _headers(Object? v) =>
    v is Map ? {for (final e in v.entries) '${e.key}': '${e.value}'} : {};

enum StreamType {
  auto('Auto detect (any link: .php, .m3u8, .mpd, .ts, .mp4…)'),
  hls('HLS playlist (.m3u8, or .php that returns one)'),
  dash('DASH (.mpd)'),
  ts('MPEG-TS live (.ts, IPTV /live/… links)'),
  smooth('Smooth Streaming (.ism/Manifest)'),
  rtsp('RTSP (rtsp://)'),
  progressive('Video file (MP4, MKV, WebM, MP3)');

  const StreamType(this.label);
  final String label;

  static StreamType parse(String v) =>
      values.firstWhere((t) => t.name == v, orElse: () => StreamType.auto);
}

enum DrmType {
  none('No DRM'),
  clearkey('ClearKey'),
  widevine('Widevine');

  const DrmType(this.label);
  final String label;

  static DrmType parse(String v) => values.firstWhere((t) => t.name == v, orElse: () => DrmType.none);
}

class Channel {
  Channel({
    this.id,
    this.name = '',
    this.category = '',
    this.imageUrl = '',
    this.premium = false,
    this.live = true,
    this.active = true,
    this.sortOrder = 0,
    this.viewers = '',
    this.streamUrl = '',
    this.streamType = StreamType.auto,
    this.drmType = DrmType.none,
    this.clearKeys = '',
    this.licenseUrl = '',
    Map<String, String>? licenseHeaders,
    this.referer = '',
    this.origin = '',
    this.userAgent = '',
    Map<String, String>? headers,
  }) : licenseHeaders = licenseHeaders ?? {},
       headers = headers ?? {};

  factory Channel.fromJson(Json j) => Channel(
    id: _int(j['id']),
    name: _str(j['name']),
    category: _str(j['category']),
    imageUrl: _str(j['imageUrl']),
    premium: j['premium'] == true,
    live: j['live'] == true,
    active: j['active'] != false,
    sortOrder: _int(j['sortOrder']),
    viewers: _str(j['viewers']),
    streamUrl: _str(j['streamUrl']),
    streamType: StreamType.parse(_str(j['streamType'])),
    drmType: DrmType.parse(_str(j['drmType'])),
    clearKeys: _str(j['clearKeys']),
    licenseUrl: _str(j['licenseUrl']),
    licenseHeaders: _headers(j['licenseHeaders']),
    referer: _str(j['referer']),
    origin: _str(j['origin']),
    userAgent: _str(j['userAgent']),
    headers: _headers(j['headers']),
  );

  final int? id;
  final String name;
  final String category;
  final String imageUrl;
  final bool premium;
  final bool live;
  final bool active;
  final int sortOrder;
  final String viewers;
  final String streamUrl;
  final StreamType streamType;
  final DrmType drmType;
  final String clearKeys;
  final String licenseUrl;
  final Map<String, String> licenseHeaders;
  final String referer;
  final String origin;
  final String userAgent;
  final Map<String, String> headers;

  Json toJson() => {
    'name': name,
    'category': category,
    'imageUrl': imageUrl,
    'premium': premium,
    'live': live,
    'active': active,
    'sortOrder': sortOrder,
    'viewers': viewers,
    'streamUrl': streamUrl,
    'streamType': streamType.name,
    'drmType': drmType.name,
    'clearKeys': clearKeys,
    'licenseUrl': licenseUrl,
    'licenseHeaders': licenseHeaders,
    'referer': referer,
    'origin': origin,
    'userAgent': userAgent,
    'headers': headers,
  };
}

class Slide {
  Slide({
    this.id,
    this.kicker = '',
    this.title = '',
    this.detail = '',
    this.imageUrl = '',
    this.channelId,
    this.sortOrder = 0,
    this.active = true,
  });

  factory Slide.fromJson(Json j) => Slide(
    id: _int(j['id']),
    kicker: _str(j['kicker']),
    title: _str(j['title']),
    detail: _str(j['detail']),
    imageUrl: _str(j['imageUrl'] ?? j['image']),
    channelId: j['channelId'] == null ? null : _int(j['channelId']),
    sortOrder: _int(j['sortOrder']),
    active: j['active'] != false,
  );

  final int? id;
  final String kicker;
  final String title;
  final String detail;
  final String imageUrl;
  final int? channelId;
  final int sortOrder;
  final bool active;

  Json toJson() => {
    'kicker': kicker,
    'title': title,
    'detail': detail,
    'imageUrl': imageUrl,
    'channelId': channelId,
    'sortOrder': sortOrder,
    'active': active,
  };
}

class Plan {
  Plan({
    this.id = '',
    this.name = '',
    this.days = 30,
    this.priceTzs = 0,
    this.quality = 'HD',
    this.description = '',
    this.recommended = false,
    this.active = true,
    this.sortOrder = 0,
  });

  factory Plan.fromJson(Json j) => Plan(
    id: _str(j['id']),
    name: _str(j['name']),
    days: _int(j['days']),
    priceTzs: _int(j['priceTzs']),
    quality: _str(j['quality']),
    description: _str(j['description']),
    recommended: j['recommended'] == true,
    active: j['active'] != false,
    sortOrder: _int(j['sortOrder']),
  );

  final String id;
  final String name;
  final int days;
  final int priceTzs;
  final String quality;
  final String description;
  final bool recommended;
  final bool active;
  final int sortOrder;

  Json toJson() => {
    'name': name,
    'days': days,
    'priceTzs': priceTzs,
    'quality': quality,
    'description': description,
    'recommended': recommended,
    'active': active,
    'sortOrder': sortOrder,
  };
}

enum UserStatus {
  premium('Premium'),
  expired('Expired'),
  free('Free'),
  blocked('Blocked');

  const UserStatus(this.label);
  final String label;

  static UserStatus parse(String v) =>
      values.firstWhere((s) => s.name == v, orElse: () => UserStatus.free);
}

class AppUser {
  AppUser({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.phone,
    required this.planId,
    required this.planName,
    required this.expiresAt,
    required this.status,
    required this.blocked,
    required this.hasPush,
    required this.platform,
    required this.appVersion,
    required this.lastSeenAt,
    required this.createdAt,
  });

  factory AppUser.fromJson(Json j) => AppUser(
    id: _int(j['id']),
    deviceId: _str(j['deviceId']),
    name: _str(j['name']),
    phone: _str(j['phone']),
    planId: j['planId'] as String?,
    planName: j['planName'] as String?,
    expiresAt: _date(j['expiresAt']),
    status: UserStatus.parse(_str(j['status'])),
    blocked: j['blocked'] == true,
    hasPush: j['hasPush'] == true,
    platform: _str(j['platform']),
    appVersion: _str(j['appVersion']),
    lastSeenAt: _date(j['lastSeenAt']),
    createdAt: _date(j['createdAt']),
  );

  final int id;
  final String deviceId;
  final String name;
  final String phone;
  final String? planId;
  final String? planName;
  final DateTime? expiresAt;
  final UserStatus status;
  final bool blocked;
  final bool hasPush;
  final String platform;
  final String appVersion;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;

  String get displayName => name.isNotEmpty ? name : deviceId;
}

class Payment {
  Payment({
    required this.id,
    required this.userId,
    required this.deviceId,
    required this.userName,
    required this.planName,
    required this.days,
    required this.amountTzs,
    required this.phone,
    required this.payerName,
    required this.provider,
    required this.orderId,
    required this.status,
    required this.message,
    required this.note,
    required this.createdAt,
    required this.paidAt,
  });

  factory Payment.fromJson(Json j) => Payment(
    id: _int(j['id']),
    userId: _int(j['userId']),
    deviceId: j['deviceId'] as String?,
    userName: j['userName'] as String?,
    planName: _str(j['planName']),
    days: _int(j['days']),
    amountTzs: _int(j['amountTzs']),
    phone: _str(j['phone']),
    payerName: _str(j['payerName']),
    provider: _str(j['provider']),
    orderId: _str(j['orderId']),
    status: _str(j['status']),
    message: _str(j['message']),
    note: _str(j['note']),
    createdAt: _date(j['createdAt']),
    paidAt: _date(j['paidAt']),
  );

  final int id;
  final int userId;
  final String? deviceId;
  final String? userName;
  final String planName;
  final int days;
  final int amountTzs;
  final String phone;
  final String payerName;
  final String provider;
  final String orderId;
  final String status;
  final String message;
  final String note;
  final DateTime? createdAt;
  final DateTime? paidAt;

  String get providerLabel => switch (provider) {
    'sonicpesa' => 'SonicPesa',
    'manual' => 'Manual',
    'admin_grant' => 'Free grant',
    _ => provider,
  };

  String get who {
    if (payerName.isNotEmpty) return payerName;
    if ((userName ?? '').isNotEmpty) return userName!;
    return deviceId ?? 'User #$userId';
  }
}

class DashboardData {
  DashboardData({required this.stats, required this.last7Days, required this.recentPayments});

  factory DashboardData.fromJson(Json j) => DashboardData(
    stats: {for (final e in (j['stats'] as Map).entries) '${e.key}': _int(e.value)},
    last7Days: [
      for (final d in j['last7Days'] as List)
        (day: DateTime.parse('${d['day']}'), revenue: _int(d['revenue'])),
    ],
    recentPayments: [for (final p in j['recentPayments'] as List) Payment.fromJson(p as Json)],
  );

  final Map<String, int> stats;
  final List<({DateTime day, int revenue})> last7Days;
  final List<Payment> recentPayments;

  int operator [](String key) => stats[key] ?? 0;
}

class NotificationLog {
  NotificationLog({
    required this.id,
    required this.title,
    required this.body,
    required this.target,
    required this.recipients,
    required this.delivered,
    required this.failed,
    required this.createdAt,
  });

  factory NotificationLog.fromJson(Json j) => NotificationLog(
    id: _int(j['id']),
    title: _str(j['title']),
    body: _str(j['body']),
    target: _str(j['target']),
    recipients: _int(j['recipients']),
    delivered: _int(j['delivered']),
    failed: _int(j['failed']),
    createdAt: _date(j['createdAt']),
  );

  final int id;
  final String title;
  final String body;
  final String target;
  final int recipients;
  final int delivered;
  final int failed;
  final DateTime? createdAt;
}

class AppSettings {
  AppSettings({
    required this.maintenanceEnabled,
    required this.maintenanceMessage,
    required this.latestVersion,
    required this.minVersion,
    required this.forceUpdate,
    required this.updateMessage,
    required this.updateUrl,
    required this.supportWhatsApp,
    required this.refreshToken,
    required this.services,
  });

  factory AppSettings.fromJson(Json j) {
    final m = (j['maintenance'] as Map?) ?? {};
    final u = (j['appUpdate'] as Map?) ?? {};
    return AppSettings(
      maintenanceEnabled: m['enabled'] == true,
      maintenanceMessage: _str(m['message']),
      latestVersion: _str(u['latestVersion']),
      minVersion: _str(u['minVersion']),
      forceUpdate: u['force'] == true,
      updateMessage: _str(u['message']),
      updateUrl: _str(u['url']),
      supportWhatsApp: _str(j['supportWhatsApp']),
      refreshToken: _int(j['refreshToken']),
      services: {
        for (final e in ((j['services'] as Map?) ?? {}).entries) '${e.key}': e.value == true,
      },
    );
  }

  final bool maintenanceEnabled;
  final String maintenanceMessage;
  final String latestVersion;
  final String minVersion;
  final bool forceUpdate;
  final String updateMessage;
  final String updateUrl;
  final String supportWhatsApp;
  final int refreshToken;
  final Map<String, bool> services;
}
