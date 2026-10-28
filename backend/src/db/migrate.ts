import { logger } from '../lib/logger';
import { getPool, query, queryOne } from './pool';

const SCHEMA = `
CREATE TABLE IF NOT EXISTS channels (
  id              SERIAL PRIMARY KEY,
  name            TEXT        NOT NULL,
  category        TEXT        NOT NULL DEFAULT 'Burudani',
  image_url       TEXT        NOT NULL DEFAULT '',
  premium         BOOLEAN     NOT NULL DEFAULT false,
  is_live         BOOLEAN     NOT NULL DEFAULT true,
  active          BOOLEAN     NOT NULL DEFAULT true,
  sort_order      INT         NOT NULL DEFAULT 0,
  viewers         TEXT        NOT NULL DEFAULT '',
  stream_url      TEXT        NOT NULL DEFAULT '',
  stream_type     TEXT        NOT NULL DEFAULT 'auto',
  drm_type        TEXT        NOT NULL DEFAULT 'none',
  clearkey_keys   TEXT        NOT NULL DEFAULT '',
  license_url     TEXT        NOT NULL DEFAULT '',
  license_headers JSONB       NOT NULL DEFAULT '{}',
  referer         TEXT        NOT NULL DEFAULT '',
  origin          TEXT        NOT NULL DEFAULT '',
  user_agent      TEXT        NOT NULL DEFAULT '',
  headers         JSONB       NOT NULL DEFAULT '{}',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS slides (
  id          SERIAL PRIMARY KEY,
  kicker      TEXT        NOT NULL DEFAULT '',
  title       TEXT        NOT NULL DEFAULT '',
  detail      TEXT        NOT NULL DEFAULT '',
  image_url   TEXT        NOT NULL,
  channel_id  INT         REFERENCES channels(id) ON DELETE SET NULL,
  sort_order  INT         NOT NULL DEFAULT 0,
  active      BOOLEAN     NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS plans (
  id          TEXT PRIMARY KEY,
  name        TEXT    NOT NULL,
  days        INT     NOT NULL,
  price_tzs   INT     NOT NULL,
  quality     TEXT    NOT NULL DEFAULT 'HD',
  description TEXT    NOT NULL DEFAULT '',
  recommended BOOLEAN NOT NULL DEFAULT false,
  active      BOOLEAN NOT NULL DEFAULT true,
  sort_order  INT     NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS users (
  id           SERIAL PRIMARY KEY,
  device_id    TEXT        NOT NULL UNIQUE,
  secret_hash  TEXT        NOT NULL,
  name         TEXT        NOT NULL DEFAULT '',
  phone        TEXT        NOT NULL DEFAULT '',
  plan_id      TEXT,
  expires_at   TIMESTAMPTZ,
  period_days  INT         NOT NULL DEFAULT 0,
  blocked      BOOLEAN     NOT NULL DEFAULT false,
  fcm_token    TEXT        NOT NULL DEFAULT '',
  platform     TEXT        NOT NULL DEFAULT '',
  app_version  TEXT        NOT NULL DEFAULT '',
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS users_expires_idx ON users (expires_at);

CREATE TABLE IF NOT EXISTS payments (
  id          SERIAL PRIMARY KEY,
  user_id     INT         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id     TEXT        NOT NULL,
  plan_name   TEXT        NOT NULL,
  days        INT         NOT NULL,
  amount_tzs  INT         NOT NULL DEFAULT 0,
  phone       TEXT        NOT NULL DEFAULT '',
  payer_name  TEXT        NOT NULL DEFAULT '',
  provider    TEXT        NOT NULL,
  order_id    TEXT        NOT NULL DEFAULT '',
  status      TEXT        NOT NULL DEFAULT 'pending',
  message     TEXT        NOT NULL DEFAULT '',
  note        TEXT        NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at     TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS payments_order_idx ON payments (order_id);
CREATE INDEX IF NOT EXISTS payments_paid_idx ON payments (status, paid_at);

CREATE TABLE IF NOT EXISTS notifications (
  id          SERIAL PRIMARY KEY,
  title       TEXT        NOT NULL,
  body        TEXT        NOT NULL DEFAULT '',
  target      TEXT        NOT NULL,
  recipients  INT         NOT NULL DEFAULT 0,
  delivered   INT         NOT NULL DEFAULT 0,
  failed      INT         NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS settings (
  key        TEXT PRIMARY KEY,
  value      JSONB       NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Images uploaded from the admin app (channel logos, carousel banners).
CREATE TABLE IF NOT EXISTS media (
  id         SERIAL PRIMARY KEY,
  mime       TEXT        NOT NULL,
  data       BYTEA       NOT NULL,
  size_bytes INT         NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Automatic renewal reminders: the expiry each user was last reminded about,
-- so every package end triggers each reminder once.
ALTER TABLE users ADD COLUMN IF NOT EXISTS reminded_expiring_for TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS reminded_expired_for  TIMESTAMPTZ;
`;

const img = (id: string, w = 900, q = 80) =>
  `https://images.unsplash.com/${id}?auto=format&fit=crop&w=${w}&q=${q}`;

const IMAGES = {
  stadium: img('photo-1599158150601-1417ebbaafdd', 1200, 85),
  field: img('photo-1569531955323-33c6b2dca44b'),
  cinema: img('photo-1489599849927-2ee91cede3ba'),
  screen: img('photo-1517604931442-7e0c8ed2963c'),
  lion: img('photo-1575550959106-5a7defe28b56'),
};

/** Public test streams so every DRM path can be tried before real channels are added. */
const DEMO_STREAMS = {
  hls: { url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8', type: 'hls' },
  clearkey: {
    url: 'https://storage.googleapis.com/shaka-demo-assets/angel-one-clearkey/dash.mpd',
    type: 'dash',
    keys: 'feedf00deedeadbeeff0baadf00dd00d:00112233445566778899aabbccddeeff',
  },
  widevine: {
    url: 'https://storage.googleapis.com/wvmedia/cenc/h264/tears/tears.mpd',
    type: 'dash',
    license: 'https://proxy.uat.widevine.com/proxy?provider=widevine_test',
  },
};

export const DEFAULT_SETTINGS: Record<string, unknown> = {
  maintenance: {
    enabled: false,
    message: 'Tunaboresha huduma zetu. Tafadhali rudi baada ya muda mfupi.',
  },
  app_update: {
    latestVersion: '1.0.0',
    minVersion: '1.0.0',
    force: false,
    message: 'Kuna toleo jipya la AyomaMax. Download sasa upate maboresho mapya.',
    url: '',
  },
  refresh: { token: 0 },
  support: { whatsapp: '255700000000' },
};

async function seed(): Promise<void> {
  const plans = await queryOne<{ n: string }>('SELECT count(*)::text AS n FROM plans');
  if (plans?.n === '0') {
    await query(
      `INSERT INTO plans (id, name, days, price_tzs, quality, description, recommended, sort_order) VALUES
        ('weekly', 'Wiki 1', 7, 2000, 'HD', 'Chaneli zote za burudani', false, 1),
        ('premium', 'Mwezi 1', 30, 5000, 'HD Kamili', 'Chaneli zote, bila matangazo', true, 2),
        ('premium_plus', 'Miezi 3', 90, 12000, 'HD Kamili', 'Bei nafuu kwa miezi 3', false, 3)`,
    );
    logger.info('seeded_plans');
  }

  const channels = await queryOne<{ n: string }>('SELECT count(*)::text AS n FROM channels');
  if (channels?.n === '0') {
    const rows: Array<[string, string, string, boolean, string, keyof typeof DEMO_STREAMS]> = [
      ['Goal Arena', 'Mpira', IMAGES.field, false, '82K', 'hls'],
      ['Cinema One', 'Filamu', IMAGES.cinema, true, '24K', 'widevine'],
      ['Sport Max', 'Mpira', IMAGES.stadium, true, '56K', 'clearkey'],
      ['Wild Earth', 'Wanyama', IMAGES.lion, false, '11K', 'hls'],
      ['Family Toon', 'Katuni', IMAGES.screen, false, '19K', 'hls'],
      ['Peace TV', 'Dini', IMAGES.screen, false, '8K', 'hls'],
    ];
    let order = 1;
    for (const [name, category, image, premium, viewers, kind] of rows) {
      const s = DEMO_STREAMS[kind];
      await query(
        `INSERT INTO channels
           (name, category, image_url, premium, viewers, sort_order,
            stream_url, stream_type, drm_type, clearkey_keys, license_url)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
        [
          name,
          category,
          image,
          premium,
          viewers,
          order++,
          s.url,
          s.type,
          kind === 'hls' ? 'none' : kind,
          'keys' in s ? s.keys : '',
          'license' in s ? s.license : '',
        ],
      );
    }
    logger.info('seeded_channels');
  }

  const slides = await queryOne<{ n: string }>('SELECT count(*)::text AS n FROM slides');
  if (slides?.n === '0') {
    await query(
      `INSERT INTO slides (kicker, title, detail, image_url, sort_order) VALUES
        ('MECHI YA LEO', 'Ligi ya Mabingwa', 'Barcelona dhidi ya Milan • Mubashara sasa', $1, 1),
        ('FILAMU MPYA', 'Usiku wa Filamu', 'Filamu mpya inaanza saa 3 usiku', $2, 2),
        ('DUNIA YA WANYAMA', 'Afrika Pori', 'Tazama wanyama wa porini mubashara', $3, 3)`,
      [IMAGES.stadium, IMAGES.cinema, IMAGES.lion],
    );
    logger.info('seeded_slides');
  }

  for (const [key, value] of Object.entries(DEFAULT_SETTINGS)) {
    await query(
      'INSERT INTO settings (key, value) VALUES ($1, $2) ON CONFLICT (key) DO NOTHING',
      [key, JSON.stringify(value)],
    );
  }
}

export async function migrate(): Promise<void> {
  await getPool().query(SCHEMA);
  await seed();
  logger.info('database_ready');
}
