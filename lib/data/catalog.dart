typedef Json = Map<String, dynamic>;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _str(Object? v) => v == null ? '' : '$v';

String formatTzs(int amount) {
  final digits = amount.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return 'TSh $buf';
}

class Plan {
  const Plan({
    required this.id,
    required this.name,
    required this.days,
    required this.priceTzs,
    required this.quality,
    required this.description,
    this.recommended = false,
  });

  factory Plan.fromJson(Json j) => Plan(
    id: _str(j['id']),
    name: _str(j['name']),
    days: _int(j['days']),
    priceTzs: _int(j['priceTzs']),
    quality: _str(j['quality']),
    description: _str(j['description']),
    recommended: j['recommended'] == true,
  );

  final String id;
  final String name;
  final int days;
  final int priceTzs;
  final String quality;
  final String description;
  final bool recommended;

  String get price => formatTzs(priceTzs);
}

class Channel {
  const Channel({
    this.id,
    required this.name,
    required this.category,
    required this.image,
    required this.premium,
  });

  factory Channel.fromJson(Json j) => Channel(
    id: _int(j['id']),
    name: _str(j['name']),
    category: _str(j['category']),
    image: _str(j['image']),
    premium: j['premium'] == true,
  );

  /// Server ID; null for the built-in offline catalog.
  final int? id;
  final String name;
  final String category;
  final String image;
  final bool premium;
}

class Slide {
  const Slide({
    required this.kicker,
    required this.title,
    required this.detail,
    required this.image,
    this.channelId,
  });

  factory Slide.fromJson(Json j) => Slide(
    kicker: _str(j['kicker']),
    title: _str(j['title']),
    detail: _str(j['detail']),
    image: _str(j['image']),
    channelId: j['channelId'] == null ? null : _int(j['channelId']),
  );

  final String kicker;
  final String title;
  final String detail;
  final String image;
  final int? channelId;
}

const allCategory = 'Zote';

/// Plans, channels and carousel shown in the app. Comes from the server and
/// falls back to [Catalog.builtIn] when offline on first launch.
class Catalog {
  const Catalog({required this.plans, required this.channels, required this.slides});

  factory Catalog.fromJson(Json j) {
    List<T> list<T>(String key, T Function(Json) parse) => [
      for (final item in (j[key] as List? ?? const [])) parse(item as Json),
    ];
    return Catalog(
      plans: list('plans', Plan.fromJson),
      channels: list('channels', Channel.fromJson),
      slides: list('slides', Slide.fromJson),
    );
  }

  static const builtIn = Catalog(plans: _plans, channels: _channels, slides: _slides);

  final List<Plan> plans;
  final List<Channel> channels;
  final List<Slide> slides;

  List<String> get categories => [
    allCategory,
    ...{for (final c in channels) c.category},
  ];

  int get recommendedIndex {
    final i = plans.indexWhere((p) => p.recommended);
    if (i >= 0) return i;
    return plans.length > 1 ? 1 : 0;
  }

  Plan get recommendedPlan => plans[recommendedIndex];

  Plan? planById(String? id) {
    for (final plan in plans) {
      if (plan.id == id) return plan;
    }
    return null;
  }

  Channel? channelById(int? id) {
    if (id == null) return null;
    for (final channel in channels) {
      if (channel.id == id) return channel;
    }
    return null;
  }
}

/// WhatsApp support number used until the server sends one.
const supportWhatsAppNumber = '255700000000';

class Imagery {
  Imagery._();

  static const stadium =
      'https://images.unsplash.com/photo-1599158150601-1417ebbaafdd?auto=format&fit=crop&w=1200&q=85';
  static const field =
      'https://images.unsplash.com/photo-1569531955323-33c6b2dca44b?auto=format&fit=crop&w=900&q=80';
  static const cinema =
      'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?auto=format&fit=crop&w=900&q=80';
  static const screen =
      'https://images.unsplash.com/photo-1517604931442-7e0c8ed2963c?auto=format&fit=crop&w=900&q=80';
  static const lion =
      'https://images.unsplash.com/photo-1575550959106-5a7defe28b56?auto=format&fit=crop&w=900&q=80';

  static const all = [stadium, field, cinema, screen, lion];
}

const _plans = <Plan>[
  Plan(
    id: 'weekly',
    name: 'Wiki 1',
    days: 7,
    priceTzs: 2000,
    quality: 'HD',
    description: 'Chaneli zote za burudani',
  ),
  Plan(
    id: 'premium',
    name: 'Mwezi 1',
    days: 30,
    priceTzs: 5000,
    quality: 'HD Kamili',
    description: 'Chaneli zote, bila matangazo',
    recommended: true,
  ),
  Plan(
    id: 'premium_plus',
    name: 'Miezi 3',
    days: 90,
    priceTzs: 12000,
    quality: 'HD Kamili',
    description: 'Bei nafuu kwa miezi 3',
  ),
];

const _slides = <Slide>[
  Slide(
    kicker: 'MECHI YA LEO',
    title: 'Ligi ya Mabingwa',
    detail: 'Barcelona dhidi ya Milan • Mubashara sasa',
    image: Imagery.stadium,
  ),
  Slide(
    kicker: 'FILAMU MPYA',
    title: 'Usiku wa Filamu',
    detail: 'Filamu mpya inaanza saa 3 usiku',
    image: Imagery.cinema,
  ),
  Slide(
    kicker: 'DUNIA YA WANYAMA',
    title: 'Afrika Pori',
    detail: 'Tazama wanyama wa porini mubashara',
    image: Imagery.lion,
  ),
];

const _channels = <Channel>[
  Channel(name: 'Goal Arena', category: 'Mpira', image: Imagery.field, premium: false),
  Channel(name: 'Cinema One', category: 'Filamu', image: Imagery.cinema, premium: true),
  Channel(name: 'Sport Max', category: 'Mpira', image: Imagery.stadium, premium: true),
  Channel(name: 'Wild Earth', category: 'Wanyama', image: Imagery.lion, premium: false),
  Channel(name: 'Family Toon', category: 'Katuni', image: Imagery.screen, premium: false),
  Channel(name: 'Peace TV', category: 'Dini', image: Imagery.screen, premium: false),
];
