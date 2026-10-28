import { userStatus } from './subscriptions';

export type ChannelRow = {
  id: number;
  name: string;
  category: string;
  image_url: string;
  premium: boolean;
  is_live: boolean;
  active: boolean;
  sort_order: number;
  viewers: string;
  stream_url: string;
  stream_type: string;
  drm_type: string;
  clearkey_keys: string;
  license_url: string;
  license_headers: Record<string, string>;
  referer: string;
  origin: string;
  user_agent: string;
  headers: Record<string, string>;
  created_at: Date;
  updated_at: Date;
};

/** What the user app may see in lists: no stream URLs or keys. */
export function publicChannel(c: ChannelRow) {
  return {
    id: c.id,
    name: c.name,
    category: c.category,
    image: c.image_url,
    premium: c.premium,
    live: c.is_live,
    viewers: c.viewers,
  };
}

export function adminChannel(c: ChannelRow) {
  return {
    id: c.id,
    name: c.name,
    category: c.category,
    imageUrl: c.image_url,
    premium: c.premium,
    live: c.is_live,
    active: c.active,
    sortOrder: c.sort_order,
    viewers: c.viewers,
    streamUrl: c.stream_url,
    streamType: c.stream_type,
    drmType: c.drm_type,
    clearKeys: c.clearkey_keys,
    licenseUrl: c.license_url,
    licenseHeaders: c.license_headers ?? {},
    referer: c.referer,
    origin: c.origin,
    userAgent: c.user_agent,
    headers: c.headers ?? {},
    createdAt: c.created_at,
    updatedAt: c.updated_at,
  };
}

/** "kid:key" pairs, one per line or comma-separated, hex or base64url. */
export function parseClearKeys(raw: string): Array<{ kid: string; key: string }> {
  return raw
    .split(/[\n,;]+/)
    .map((pair) => pair.trim())
    .filter(Boolean)
    .map((pair) => {
      const [kid = '', key = ''] = pair.split(':').map((p) => p.trim());
      return { kid, key };
    })
    .filter((p) => p.kid && p.key);
}

/** Everything the native player needs to open a channel. */
export function playbackConfig(c: ChannelRow) {
  const headers: Record<string, string> = { ...(c.headers ?? {}) };
  if (c.referer) headers.Referer = c.referer;
  if (c.origin) headers.Origin = c.origin;
  if (c.user_agent) headers['User-Agent'] = c.user_agent;
  return {
    channelId: c.id,
    name: c.name,
    url: c.stream_url,
    streamType: c.stream_type,
    headers,
    drm: {
      type: c.drm_type,
      licenseUrl: c.license_url,
      licenseHeaders: c.license_headers ?? {},
      clearKeys: c.drm_type === 'clearkey' ? parseClearKeys(c.clearkey_keys) : [],
    },
  };
}

export type SlideRow = {
  id: number;
  kicker: string;
  title: string;
  detail: string;
  image_url: string;
  channel_id: number | null;
  sort_order: number;
  active: boolean;
};

export function publicSlide(s: SlideRow) {
  return {
    id: s.id,
    kicker: s.kicker,
    title: s.title,
    detail: s.detail,
    image: s.image_url,
    channelId: s.channel_id,
  };
}

export function adminSlide(s: SlideRow) {
  return { ...publicSlide(s), imageUrl: s.image_url, sortOrder: s.sort_order, active: s.active };
}

export type PlanRow = {
  id: string;
  name: string;
  days: number;
  price_tzs: number;
  quality: string;
  description: string;
  recommended: boolean;
  active: boolean;
  sort_order: number;
};

export function publicPlan(p: PlanRow) {
  return {
    id: p.id,
    name: p.name,
    days: p.days,
    priceTzs: p.price_tzs,
    quality: p.quality,
    description: p.description,
    recommended: p.recommended,
  };
}

export function adminPlan(p: PlanRow) {
  return { ...publicPlan(p), active: p.active, sortOrder: p.sort_order };
}

export type UserRow = {
  id: number;
  device_id: string;
  name: string;
  phone: string;
  plan_id: string | null;
  expires_at: Date | null;
  period_days: number;
  blocked: boolean;
  fcm_token: string;
  platform: string;
  app_version: string;
  last_seen_at: Date;
  created_at: Date;
};

export function appUser(u: UserRow) {
  return {
    deviceId: u.device_id,
    name: u.name,
    phone: u.phone,
    planId: u.plan_id,
    expiresAt: u.expires_at,
    periodDays: u.period_days,
    blocked: u.blocked,
  };
}

export function adminUser(u: UserRow & { plan_name?: string | null }) {
  return {
    id: u.id,
    deviceId: u.device_id,
    name: u.name,
    phone: u.phone,
    planId: u.plan_id,
    planName: u.plan_name ?? null,
    expiresAt: u.expires_at,
    periodDays: u.period_days,
    status: userStatus(u),
    blocked: u.blocked,
    hasPush: u.fcm_token.length > 0,
    platform: u.platform,
    appVersion: u.app_version,
    lastSeenAt: u.last_seen_at,
    createdAt: u.created_at,
  };
}

export type PaymentRow = {
  id: number;
  user_id: number;
  plan_id: string;
  plan_name: string;
  days: number;
  amount_tzs: number;
  phone: string;
  payer_name: string;
  provider: string;
  order_id: string;
  status: string;
  message: string;
  note: string;
  created_at: Date;
  paid_at: Date | null;
};

export function appPayment(p: PaymentRow) {
  return {
    id: p.id,
    planId: p.plan_id,
    planName: p.plan_name,
    amountTzs: p.amount_tzs,
    status: p.status,
    message: p.message,
    createdAt: p.created_at,
    paidAt: p.paid_at,
  };
}

export function adminPayment(p: PaymentRow & { device_id?: string; user_name?: string }) {
  return {
    ...appPayment(p),
    userId: p.user_id,
    deviceId: p.device_id ?? null,
    userName: p.user_name ?? null,
    days: p.days,
    phone: p.phone,
    payerName: p.payer_name,
    provider: p.provider,
    orderId: p.order_id,
    note: p.note,
  };
}
