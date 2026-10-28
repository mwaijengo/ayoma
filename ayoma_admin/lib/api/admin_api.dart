import 'api_client.dart';
import 'models.dart';

typedef UserPage = ({int total, List<AppUser> users});
typedef PaymentPage = ({int total, int totalPaidTzs, List<Payment> payments});
typedef PushSummary = ({int recipients, int delivered, int failed});

PushSummary _push(Object? j) {
  final m = (j as Map?) ?? const {};
  int n(String k) => (m[k] as num?)?.toInt() ?? 0;
  return (recipients: n('recipients'), delivered: n('delivered'), failed: n('failed'));
}

/// Typed wrapper over `/api/v1/admin`.
class AdminApi {
  AdminApi(this.client);

  final ApiClient client;

  Future<DashboardData> dashboard() async =>
      DashboardData.fromJson(await client.get('/admin/dashboard'));

  // Channels
  Future<List<Channel>> channels() async {
    final res = await client.get('/admin/channels');
    return [for (final c in res['channels'] as List) Channel.fromJson(c as Json)];
  }

  Future<Channel> saveChannel(Channel c) async {
    final res = c.id == null
        ? await client.post('/admin/channels', c.toJson())
        : await client.put('/admin/channels/${c.id}', c.toJson());
    return Channel.fromJson(res['channel'] as Json);
  }

  Future<void> setChannelActive(int id, bool active) =>
      client.patch('/admin/channels/$id/active', {'active': active});

  Future<void> deleteChannel(int id) => client.delete('/admin/channels/$id');

  // Carousel
  Future<List<Slide>> slides() async {
    final res = await client.get('/admin/slides');
    return [for (final s in res['slides'] as List) Slide.fromJson(s as Json)];
  }

  /// Stores an image on the server and returns its public URL.
  Future<String> uploadImage(List<int> bytes, String contentType) async {
    final res = await client.postBytes('/media', bytes, contentType);
    return (res['media'] as Json)['url'] as String;
  }

  Future<void> saveSlide(Slide s) => s.id == null
      ? client.post('/admin/slides', s.toJson())
      : client.put('/admin/slides/${s.id}', s.toJson());

  Future<void> deleteSlide(int id) => client.delete('/admin/slides/$id');

  // Packages
  Future<List<Plan>> plans() async {
    final res = await client.get('/admin/plans');
    return [for (final p in res['plans'] as List) Plan.fromJson(p as Json)];
  }

  Future<void> savePlan(Plan p, {required bool isNew}) => isNew
      ? client.post('/admin/plans', {'id': p.id, ...p.toJson()})
      : client.put('/admin/plans/${p.id}', p.toJson());

  /// Returns true when the package was only hidden because payments use it.
  Future<bool> deletePlan(String id) async {
    final res = await client.delete('/admin/plans/$id');
    return res['deactivated'] == true;
  }

  // Users
  Future<UserPage> users({String search = '', String filter = 'all', int offset = 0}) async {
    final res = await client.get('/admin/users', {
      'search': search,
      'filter': filter,
      'offset': offset,
      'limit': 50,
    });
    return (
      total: (res['total'] as num).toInt(),
      users: [for (final u in res['users'] as List) AppUser.fromJson(u as Json)],
    );
  }

  Future<({AppUser user, List<Payment> payments})> user(int id) async {
    final res = await client.get('/admin/users/$id');
    return (
      user: AppUser.fromJson(res['user'] as Json),
      payments: [for (final p in res['payments'] as List) Payment.fromJson(p as Json)],
    );
  }

  Future<AppUser> grant(int userId, {required String planId, int? days, String? note}) async {
    final res = await client.post('/admin/users/$userId/grant', {
      'planId': planId,
      'days': ?days,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return AppUser.fromJson(res['user'] as Json);
  }

  Future<AppUser> removeSubscription(int userId) async {
    final res = await client.delete('/admin/users/$userId/subscription');
    return AppUser.fromJson(res['user'] as Json);
  }

  Future<AppUser> setBlocked(int userId, bool blocked) async {
    final res = await client.patch('/admin/users/$userId/blocked', {'blocked': blocked});
    return AppUser.fromJson(res['user'] as Json);
  }

  Future<void> deleteUser(int userId) => client.delete('/admin/users/$userId');

  // Payments
  Future<PaymentPage> payments({String status = 'all', String search = '', int offset = 0}) async {
    final res = await client.get('/admin/payments', {
      'status': status,
      'search': search,
      'offset': offset,
      'limit': 50,
    });
    return (
      total: (res['total'] as num).toInt(),
      totalPaidTzs: (res['totalPaidTzs'] as num).toInt(),
      payments: [for (final p in res['payments'] as List) Payment.fromJson(p as Json)],
    );
  }

  Future<void> confirmPayment(int id) => client.post('/admin/payments/$id/confirm');

  Future<void> manualPayment({
    required int userId,
    required String planId,
    int? amountTzs,
    String? phone,
    String? note,
  }) => client.post('/admin/payments/manual', {
    'userId': userId,
    'planId': planId,
    'amountTzs': ?amountTzs,
    if (phone != null && phone.isNotEmpty) 'phone': phone,
    if (note != null && note.isNotEmpty) 'note': note,
  });

  // Notifications
  Future<({bool pushConfigured, List<NotificationLog> items})> notifications() async {
    final res = await client.get('/admin/notifications');
    return (
      pushConfigured: res['pushConfigured'] == true,
      items: [for (final n in res['notifications'] as List) NotificationLog.fromJson(n as Json)],
    );
  }

  Future<PushSummary> sendNotification({
    required String title,
    required String body,
    required String target,
    int? userId,
  }) async {
    final res = await client.post('/admin/notifications', {
      'title': title,
      'body': body,
      'target': target,
      'userId': ?userId,
    });
    return _push(res['result']);
  }

  Future<PushSummary> resendNotification(int id) async {
    final res = await client.post('/admin/notifications/$id/resend');
    return _push(res['result']);
  }

  Future<void> clearNotifications() => client.delete('/admin/notifications');

  Future<({PushSummary expired, PushSummary expiring})> remindExpired() async {
    final res = await client.post('/admin/notifications/remind');
    return (expired: _push(res['expired']), expiring: _push(res['expiring']));
  }

  // Settings and controls
  Future<AppSettings> settings() async =>
      AppSettings.fromJson((await client.get('/admin/settings'))['settings'] as Json);

  Future<AppSettings> updateSettings(Json patch) async =>
      AppSettings.fromJson((await client.put('/admin/settings', patch))['settings'] as Json);

  Future<bool> refreshApps() async => (await client.post('/admin/refresh-apps'))['pushed'] == true;

  Future<int> downgradeAll() async {
    final res = await client.post('/admin/danger/downgrade-all', {'confirm': 'DOWNGRADE'});
    return (res['downgraded'] as num).toInt();
  }
}
