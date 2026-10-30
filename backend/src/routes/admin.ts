import { Router } from 'express';
import { z } from 'zod';

import { BUSINESS_TZ } from '../config/env';
import { query, queryOne } from '../db/pool';
import { HttpError, intParam, route } from '../lib/http';
import { logger } from '../lib/logger';
import { requireAdmin } from '../middleware/auth';
import {
  NOTIFICATION_TARGETS,
  type NotificationTarget,
  pushRefreshCommand,
  REMINDERS,
  sendNotification,
} from '../services/notifications';
import { markPaid, recordAdminPayment } from '../services/payments';
import { pushConfigured } from '../services/push';
import {
  adminChannel,
  adminPayment,
  adminPlan,
  adminSlide,
  adminUser,
  type ChannelRow,
  type PaymentRow,
  type PlanRow,
  type SlideRow,
  type UserRow,
} from '../services/serializers';
import { bumpRefreshToken, getSetting, setSetting } from '../services/settings';
import { sonicPesaConfigured, webhookSigningSecret } from '../services/sonicPesa';

export const adminRouter = Router();
adminRouter.use(requireAdmin);

const startOfToday = `(date_trunc('day', now() AT TIME ZONE '${BUSINESS_TZ}') AT TIME ZONE '${BUSINESS_TZ}')`;
const startOfMonth = `(date_trunc('month', now() AT TIME ZONE '${BUSINESS_TZ}') AT TIME ZONE '${BUSINESS_TZ}')`;
/** Revenue counts real money only, not free admin grants. */
const REVENUE = `status = 'paid' AND provider <> 'admin_grant'`;

/**
 * Deletes images uploaded from the admin app once no channel or banner uses
 * them any more, so removed content does not linger in the database.
 */
async function dropUnusedMedia(...urls: Array<string | null | undefined>): Promise<void> {
  const ids = new Set<number>();
  for (const url of urls) {
    const match = /\/api\/v1\/media\/(\d+)\/?$/.exec(url ?? '');
    if (match) ids.add(Number(match[1]));
  }
  for (const id of ids) {
    const used = `%/api/v1/media/${id}`;
    await query(
      `DELETE FROM media WHERE id = $1
         AND NOT EXISTS (SELECT 1 FROM channels WHERE image_url LIKE $2 OR image_url LIKE $2 || '/')
         AND NOT EXISTS (SELECT 1 FROM slides WHERE image_url LIKE $2 OR image_url LIKE $2 || '/')`,
      [id, used],
    );
  }
}

// ───────────────────────────── Dashboard ─────────────────────────────

adminRouter.get(
  '/dashboard',
  route(async (_req, res) => {
    const stats = await queryOne<Record<string, string>>(`
      SELECT
        (SELECT COALESCE(SUM(amount_tzs), 0) FROM payments WHERE ${REVENUE} AND paid_at >= ${startOfToday})::text AS revenue_today,
        (SELECT COUNT(*) FROM payments WHERE ${REVENUE} AND paid_at >= ${startOfToday})::text AS payments_today,
        (SELECT COALESCE(SUM(amount_tzs), 0) FROM payments WHERE ${REVENUE} AND paid_at >= ${startOfMonth})::text AS revenue_month,
        (SELECT COALESCE(SUM(amount_tzs), 0) FROM payments WHERE ${REVENUE})::text AS revenue_total,
        (SELECT COUNT(*) FROM payments WHERE status = 'pending' AND created_at > now() - interval '1 day')::text AS payments_pending,
        (SELECT COUNT(*) FROM users)::text AS users_total,
        (SELECT COUNT(*) FROM users WHERE created_at >= ${startOfToday})::text AS users_today,
        (SELECT COUNT(*) FROM users WHERE expires_at > now())::text AS premium_active,
        (SELECT COUNT(*) FROM users WHERE expires_at > now() AND expires_at <= now() + interval '3 days')::text AS expiring_soon,
        (SELECT COUNT(*) FROM users WHERE expires_at <= now())::text AS expired,
        (SELECT COUNT(*) FROM users WHERE last_seen_at > now() - interval '10 minutes')::text AS online_now,
        (SELECT COUNT(*) FROM channels WHERE active)::text AS channels_active
    `);
    const daily = await query<{ day: string; revenue: string }>(`
      SELECT to_char(d.day, 'YYYY-MM-DD') AS day,
             COALESCE(SUM(p.amount_tzs), 0)::text AS revenue
      FROM generate_series(${startOfToday} - interval '6 days', ${startOfToday}, interval '1 day') AS d(day)
      LEFT JOIN payments p
        ON p.status = 'paid' AND p.provider <> 'admin_grant'
       AND p.paid_at >= d.day AND p.paid_at < d.day + interval '1 day'
      GROUP BY d.day ORDER BY d.day
    `);
    const recent = await query<PaymentRow & { device_id: string; user_name: string }>(`
      SELECT p.*, u.device_id, u.name AS user_name FROM payments p
      JOIN users u ON u.id = p.user_id
      ORDER BY p.created_at DESC LIMIT 8
    `);
    const n = (k: string) => Number(stats?.[k] ?? 0);
    res.json({
      ok: true,
      stats: {
        revenueToday: n('revenue_today'),
        paymentsToday: n('payments_today'),
        revenueMonth: n('revenue_month'),
        revenueTotal: n('revenue_total'),
        paymentsPending: n('payments_pending'),
        usersTotal: n('users_total'),
        usersToday: n('users_today'),
        premiumActive: n('premium_active'),
        expiringSoon: n('expiring_soon'),
        expired: n('expired'),
        onlineNow: n('online_now'),
        channelsActive: n('channels_active'),
      },
      last7Days: daily.map((d) => ({ day: d.day, revenue: Number(d.revenue) })),
      recentPayments: recent.map(adminPayment),
    });
  }),
);

// ───────────────────────────── Channels ─────────────────────────────

const headerMap = z.record(z.string(), z.string()).default({});

const channelBody = z
  .object({
    name: z.string().trim().min(1).max(80),
    category: z.string().trim().min(1).max(40),
    imageUrl: z.string().trim().url().or(z.literal('')).default(''),
    premium: z.boolean().default(false),
    live: z.boolean().default(true),
    active: z.boolean().default(true),
    sortOrder: z.number().int().default(0),
    viewers: z.string().trim().max(12).default(''),
    streamUrl: z.string().trim().url(),
    streamType: z.enum(['auto', 'hls', 'dash', 'ts', 'smooth', 'rtsp', 'progressive']).default('auto'),
    drmType: z.enum(['none', 'clearkey', 'widevine']).default('none'),
    clearKeys: z.string().trim().default(''),
    licenseUrl: z.string().trim().url().or(z.literal('')).default(''),
    licenseHeaders: headerMap,
    referer: z.string().trim().default(''),
    origin: z.string().trim().default(''),
    userAgent: z.string().trim().default(''),
    headers: headerMap,
  })
  .superRefine((c, ctx) => {
    if (c.drmType === 'clearkey' && !c.clearKeys && !c.licenseUrl) {
      ctx.addIssue({
        code: 'custom',
        path: ['clearKeys'],
        message: 'ClearKey needs keys (kid:key) or a license URL',
      });
    }
  });

function channelValues(c: z.infer<typeof channelBody>): unknown[] {
  return [
    c.name,
    c.category,
    c.imageUrl,
    c.premium,
    c.live,
    c.active,
    c.sortOrder,
    c.viewers,
    c.streamUrl,
    c.streamType,
    c.drmType,
    c.drmType === 'clearkey' ? c.clearKeys : '',
    c.drmType === 'none' ? '' : c.licenseUrl,
    JSON.stringify(c.drmType === 'none' ? {} : c.licenseHeaders),
    c.referer,
    c.origin,
    c.userAgent,
    JSON.stringify(c.headers),
  ];
}

adminRouter.get(
  '/channels',
  route(async (_req, res) => {
    const rows = await query<ChannelRow>('SELECT * FROM channels ORDER BY sort_order, id');
    res.json({ ok: true, channels: rows.map(adminChannel) });
  }),
);

adminRouter.post(
  '/channels',
  route(async (req, res) => {
    const body = channelBody.parse(req.body);
    const row = await queryOne<ChannelRow>(
      `INSERT INTO channels
         (name, category, image_url, premium, is_live, active, sort_order, viewers,
          stream_url, stream_type, drm_type, clearkey_keys, license_url, license_headers,
          referer, origin, user_agent, headers)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18) RETURNING *`,
      channelValues(body),
    );
    res.status(201).json({ ok: true, channel: adminChannel(row!) });
  }),
);

adminRouter.put(
  '/channels/:id',
  route(async (req, res) => {
    const body = channelBody.parse(req.body);
    const before = await queryOne<{ image_url: string }>('SELECT image_url FROM channels WHERE id = $1', [
      intParam(req, 'id'),
    ]);
    const row = await queryOne<ChannelRow>(
      `UPDATE channels SET
         name=$1, category=$2, image_url=$3, premium=$4, is_live=$5, active=$6, sort_order=$7,
         viewers=$8, stream_url=$9, stream_type=$10, drm_type=$11, clearkey_keys=$12,
         license_url=$13, license_headers=$14, referer=$15, origin=$16, user_agent=$17,
         headers=$18, updated_at=now()
       WHERE id=$19 RETURNING *`,
      [...channelValues(body), intParam(req, 'id')],
    );
    if (!row) throw new HttpError(404, 'Channel not found', 'NOT_FOUND');
    if (before && before.image_url !== row.image_url) await dropUnusedMedia(before.image_url);
    res.json({ ok: true, channel: adminChannel(row) });
  }),
);

adminRouter.patch(
  '/channels/:id/active',
  route(async (req, res) => {
    const { active } = z.object({ active: z.boolean() }).parse(req.body);
    const row = await queryOne<ChannelRow>(
      'UPDATE channels SET active = $2, updated_at = now() WHERE id = $1 RETURNING *',
      [intParam(req, 'id'), active],
    );
    if (!row) throw new HttpError(404, 'Channel not found', 'NOT_FOUND');
    res.json({ ok: true, channel: adminChannel(row) });
  }),
);

adminRouter.delete(
  '/channels/:id',
  route(async (req, res) => {
    const rows = await query<{ image_url: string }>('DELETE FROM channels WHERE id = $1 RETURNING image_url', [
      intParam(req, 'id'),
    ]);
    if (rows.length === 0) throw new HttpError(404, 'Channel not found', 'NOT_FOUND');
    await dropUnusedMedia(rows[0]!.image_url);
    res.json({ ok: true });
  }),
);

// ───────────────────────────── Carousel ─────────────────────────────

const slideBody = z.object({
  kicker: z.string().trim().max(40).default(''),
  title: z.string().trim().max(80).default(''),
  detail: z.string().trim().max(160).default(''),
  imageUrl: z.string().trim().url(),
  channelId: z.number().int().positive().nullable().default(null),
  sortOrder: z.number().int().default(0),
  active: z.boolean().default(true),
});

adminRouter.get(
  '/slides',
  route(async (_req, res) => {
    const rows = await query<SlideRow>('SELECT * FROM slides ORDER BY sort_order, id');
    res.json({ ok: true, slides: rows.map(adminSlide) });
  }),
);

adminRouter.post(
  '/slides',
  route(async (req, res) => {
    const s = slideBody.parse(req.body);
    const row = await queryOne<SlideRow>(
      `INSERT INTO slides (kicker, title, detail, image_url, channel_id, sort_order, active)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [s.kicker, s.title, s.detail, s.imageUrl, s.channelId, s.sortOrder, s.active],
    );
    res.status(201).json({ ok: true, slide: adminSlide(row!) });
  }),
);

adminRouter.put(
  '/slides/:id',
  route(async (req, res) => {
    const s = slideBody.parse(req.body);
    const before = await queryOne<{ image_url: string }>('SELECT image_url FROM slides WHERE id = $1', [
      intParam(req, 'id'),
    ]);
    const row = await queryOne<SlideRow>(
      `UPDATE slides SET kicker=$1, title=$2, detail=$3, image_url=$4, channel_id=$5,
         sort_order=$6, active=$7 WHERE id=$8 RETURNING *`,
      [s.kicker, s.title, s.detail, s.imageUrl, s.channelId, s.sortOrder, s.active, intParam(req, 'id')],
    );
    if (!row) throw new HttpError(404, 'Slide not found', 'NOT_FOUND');
    if (before && before.image_url !== row.image_url) await dropUnusedMedia(before.image_url);
    res.json({ ok: true, slide: adminSlide(row) });
  }),
);

adminRouter.delete(
  '/slides/:id',
  route(async (req, res) => {
    const rows = await query<{ image_url: string }>('DELETE FROM slides WHERE id = $1 RETURNING image_url', [
      intParam(req, 'id'),
    ]);
    if (rows.length === 0) throw new HttpError(404, 'Slide not found', 'NOT_FOUND');
    await dropUnusedMedia(rows[0]!.image_url);
    res.json({ ok: true });
  }),
);

// ───────────────────────────── Packages ─────────────────────────────

const planBody = z.object({
  name: z.string().trim().min(1).max(40),
  days: z.number().int().min(1).max(3650),
  priceTzs: z.number().int().min(0),
  quality: z.string().trim().max(30).default('HD'),
  description: z.string().trim().max(120).default(''),
  recommended: z.boolean().default(false),
  active: z.boolean().default(true),
  sortOrder: z.number().int().default(0),
});

async function clearOtherRecommended(id: string, recommended: boolean): Promise<void> {
  if (recommended) await query('UPDATE plans SET recommended = false WHERE id <> $1', [id]);
}

adminRouter.get(
  '/plans',
  route(async (_req, res) => {
    const rows = await query<PlanRow>('SELECT * FROM plans ORDER BY sort_order, price_tzs');
    res.json({ ok: true, plans: rows.map(adminPlan) });
  }),
);

adminRouter.post(
  '/plans',
  route(async (req, res) => {
    const p = planBody
      .extend({ id: z.string().trim().regex(/^[a-z0-9_]{2,30}$/, 'Use lowercase letters, numbers, _') })
      .parse(req.body);
    const exists = await queryOne('SELECT 1 FROM plans WHERE id = $1', [p.id]);
    if (exists) throw new HttpError(409, 'A package with this ID already exists', 'DUPLICATE');
    const row = await queryOne<PlanRow>(
      `INSERT INTO plans (id, name, days, price_tzs, quality, description, recommended, active, sort_order)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
      [p.id, p.name, p.days, p.priceTzs, p.quality, p.description, p.recommended, p.active, p.sortOrder],
    );
    await clearOtherRecommended(p.id, p.recommended);
    res.status(201).json({ ok: true, plan: adminPlan(row!) });
  }),
);

adminRouter.put(
  '/plans/:id',
  route(async (req, res) => {
    const p = planBody.parse(req.body);
    const id = String(req.params.id);
    const row = await queryOne<PlanRow>(
      `UPDATE plans SET name=$1, days=$2, price_tzs=$3, quality=$4, description=$5,
         recommended=$6, active=$7, sort_order=$8 WHERE id=$9 RETURNING *`,
      [p.name, p.days, p.priceTzs, p.quality, p.description, p.recommended, p.active, p.sortOrder, id],
    );
    if (!row) throw new HttpError(404, 'Package not found', 'NOT_FOUND');
    await clearOtherRecommended(id, p.recommended);
    res.json({ ok: true, plan: adminPlan(row) });
  }),
);

adminRouter.delete(
  '/plans/:id',
  route(async (req, res) => {
    // Payments keep their own copy of the package name and days, and users keep
    // the time they already paid for, so the package itself can go for good.
    const id = String(req.params.id);
    const rows = await query('DELETE FROM plans WHERE id = $1 RETURNING id', [id]);
    if (rows.length === 0) throw new HttpError(404, 'Package not found', 'NOT_FOUND');
    res.json({ ok: true });
  }),
);

// ───────────────────────────── Users ─────────────────────────────

const USER_FILTERS: Record<string, string> = {
  all: 'true',
  premium: 'u.expires_at > now() AND NOT u.blocked',
  expiring: "u.expires_at > now() AND u.expires_at <= now() + interval '3 days'",
  expired: 'u.expires_at <= now()',
  free: 'u.expires_at IS NULL AND NOT u.blocked',
  blocked: 'u.blocked',
};

/** Falls back to the last paid package name when that package was deleted. */
const USER_SELECT = `SELECT u.*, COALESCE(p.name, (
    SELECT pm.plan_name FROM payments pm
    WHERE pm.user_id = u.id AND pm.plan_id = u.plan_id AND pm.status = 'paid'
    ORDER BY pm.paid_at DESC NULLS LAST LIMIT 1
  )) AS plan_name
  FROM users u LEFT JOIN plans p ON p.id = u.plan_id`;

adminRouter.get(
  '/users',
  route(async (req, res) => {
    const q = z
      .object({
        search: z.string().trim().default(''),
        filter: z.enum(['all', 'premium', 'expiring', 'expired', 'free', 'blocked']).default('all'),
        limit: z.coerce.number().int().min(1).max(200).default(50),
        offset: z.coerce.number().int().min(0).default(0),
      })
      .parse(req.query);
    const where = [USER_FILTERS[q.filter]!];
    const params: unknown[] = [];
    if (q.search) {
      params.push(`%${q.search}%`);
      where.push(`(u.device_id ILIKE $1 OR u.name ILIKE $1 OR u.phone ILIKE $1)`);
    }
    const whereSql = where.join(' AND ');
    const total = await queryOne<{ n: string }>(
      `SELECT count(*)::text AS n FROM users u WHERE ${whereSql}`,
      params,
    );
    const rows = await query<UserRow & { plan_name: string | null }>(
      `${USER_SELECT} WHERE ${whereSql} ORDER BY u.last_seen_at DESC
       LIMIT ${q.limit} OFFSET ${q.offset}`,
      params,
    );
    res.json({ ok: true, total: Number(total?.n ?? 0), users: rows.map(adminUser) });
  }),
);

async function loadUser(id: number) {
  const user = await queryOne<UserRow & { plan_name: string | null }>(`${USER_SELECT} WHERE u.id = $1`, [id]);
  if (!user) throw new HttpError(404, 'User not found', 'NOT_FOUND');
  return user;
}

adminRouter.get(
  '/users/:id',
  route(async (req, res) => {
    const user = await loadUser(intParam(req, 'id'));
    const payments = await query<PaymentRow>(
      'SELECT * FROM payments WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50',
      [user.id],
    );
    res.json({ ok: true, user: adminUser(user), payments: payments.map(adminPayment) });
  }),
);

/** Grant a package (or custom days) without payment. */
adminRouter.post(
  '/users/:id/grant',
  route(async (req, res) => {
    const body = z
      .object({
        planId: z.string().min(1),
        days: z.number().int().min(1).max(3650).optional(),
        note: z.string().max(200).optional(),
      })
      .parse(req.body);
    const id = intParam(req, 'id');
    await loadUser(id);
    await recordAdminPayment({ userId: id, ...body, grant: true });
    res.json({ ok: true, user: adminUser(await loadUser(id)) });
  }),
);

adminRouter.delete(
  '/users/:id/subscription',
  route(async (req, res) => {
    const id = intParam(req, 'id');
    await loadUser(id);
    await query('UPDATE users SET plan_id = NULL, expires_at = NULL, period_days = 0 WHERE id = $1', [id]);
    res.json({ ok: true, user: adminUser(await loadUser(id)) });
  }),
);

adminRouter.patch(
  '/users/:id/blocked',
  route(async (req, res) => {
    const { blocked } = z.object({ blocked: z.boolean() }).parse(req.body);
    const id = intParam(req, 'id');
    await loadUser(id);
    await query('UPDATE users SET blocked = $2 WHERE id = $1', [id, blocked]);
    res.json({ ok: true, user: adminUser(await loadUser(id)) });
  }),
);

adminRouter.delete(
  '/users/:id',
  route(async (req, res) => {
    const rows = await query('DELETE FROM users WHERE id = $1 RETURNING id', [intParam(req, 'id')]);
    if (rows.length === 0) throw new HttpError(404, 'User not found', 'NOT_FOUND');
    res.json({ ok: true });
  }),
);

// ───────────────────────────── Payments ─────────────────────────────

adminRouter.get(
  '/payments',
  route(async (req, res) => {
    const q = z
      .object({
        status: z.enum(['all', 'paid', 'pending', 'failed']).default('all'),
        search: z.string().trim().default(''),
        limit: z.coerce.number().int().min(1).max(200).default(50),
        offset: z.coerce.number().int().min(0).default(0),
      })
      .parse(req.query);
    const where: string[] = ['true'];
    const params: unknown[] = [];
    if (q.status !== 'all') {
      params.push(q.status);
      where.push(`p.status = $${params.length}`);
    }
    if (q.search) {
      params.push(`%${q.search}%`);
      const i = params.length;
      where.push(`(p.phone ILIKE $${i} OR p.order_id ILIKE $${i} OR u.device_id ILIKE $${i} OR u.name ILIKE $${i})`);
    }
    const whereSql = where.join(' AND ');
    const total = await queryOne<{ n: string; sum: string }>(
      `SELECT count(*)::text AS n,
              COALESCE(SUM(p.amount_tzs) FILTER (WHERE p.status = 'paid' AND p.provider <> 'admin_grant'), 0)::text AS sum
       FROM payments p JOIN users u ON u.id = p.user_id WHERE ${whereSql}`,
      params,
    );
    const rows = await query<PaymentRow & { device_id: string; user_name: string }>(
      `SELECT p.*, u.device_id, u.name AS user_name FROM payments p
       JOIN users u ON u.id = p.user_id WHERE ${whereSql}
       ORDER BY p.created_at DESC LIMIT ${q.limit} OFFSET ${q.offset}`,
      params,
    );
    res.json({
      ok: true,
      total: Number(total?.n ?? 0),
      totalPaidTzs: Number(total?.sum ?? 0),
      payments: rows.map(adminPayment),
    });
  }),
);

/** Confirm a pending mobile payment by hand, e.g. after checking the SonicPesa dashboard. */
adminRouter.post(
  '/payments/:id/confirm',
  route(async (req, res) => {
    const id = intParam(req, 'id');
    const payment = await queryOne<PaymentRow>('SELECT * FROM payments WHERE id = $1', [id]);
    if (!payment) throw new HttpError(404, 'Payment not found', 'NOT_FOUND');
    if (payment.status === 'paid') throw new HttpError(409, 'Already paid', 'ALREADY_PAID');
    await query(`UPDATE payments SET status = 'pending' WHERE id = $1`, [id]);
    await markPaid(id);
    res.json({ ok: true });
  }),
);

/** Record a payment received outside the app (cash, direct transfer). */
adminRouter.post(
  '/payments/manual',
  route(async (req, res) => {
    const body = z
      .object({
        userId: z.number().int().positive(),
        planId: z.string().min(1),
        amountTzs: z.number().int().min(0).optional(),
        phone: z.string().max(20).optional(),
        note: z.string().max(200).optional(),
      })
      .parse(req.body);
    await loadUser(body.userId);
    const payment = await recordAdminPayment({ ...body, grant: false });
    res.status(201).json({ ok: true, payment: adminPayment(payment) });
  }),
);

// ───────────────────────────── Notifications ─────────────────────────────

adminRouter.get(
  '/notifications',
  route(async (_req, res) => {
    const rows = await query('SELECT * FROM notifications ORDER BY created_at DESC LIMIT 100');
    res.json({
      ok: true,
      pushConfigured: pushConfigured(),
      notifications: rows.map((n) => ({
        id: n.id,
        title: n.title,
        body: n.body,
        target: n.target,
        recipients: n.recipients,
        delivered: n.delivered,
        failed: n.failed,
        createdAt: n.created_at,
      })),
    });
  }),
);

adminRouter.post(
  '/notifications',
  route(async (req, res) => {
    const body = z
      .object({
        title: z.string().trim().min(1).max(100),
        body: z.string().trim().max(500).default(''),
        target: z.enum(NOTIFICATION_TARGETS),
        userId: z.number().int().positive().optional(),
      })
      .parse(req.body);
    const result = await sendNotification(body);
    res.json({ ok: true, result });
  }),
);

adminRouter.delete(
  '/notifications',
  route(async (_req, res) => {
    const rows = await query('DELETE FROM notifications RETURNING id');
    logger.warn({ count: rows.length }, 'admin_notifications_cleared');
    res.json({ ok: true, deleted: rows.length });
  }),
);

/** Sends a past notification again to the same audience (re-evaluated now). */
adminRouter.post(
  '/notifications/:id/resend',
  route(async (req, res) => {
    const row = await queryOne<{ title: string; body: string; target: string }>(
      'SELECT title, body, target FROM notifications WHERE id = $1',
      [intParam(req, 'id')],
    );
    if (!row) throw new HttpError(404, 'Notification not found', 'NOT_FOUND');

    let target: NotificationTarget;
    let userId: number | undefined;
    if (row.target.startsWith('user:')) {
      target = 'user';
      userId = Number(row.target.slice(5));
    } else if (row.target.startsWith('auto:')) {
      target = row.target.slice(5) as NotificationTarget;
    } else {
      target = row.target as NotificationTarget;
    }
    if (!NOTIFICATION_TARGETS.includes(target) || (target === 'user' && !userId)) {
      throw new HttpError(400, 'This notification cannot be resent', 'BAD_TARGET');
    }
    const result = await sendNotification({ title: row.title, body: row.body, target, userId });
    res.json({ ok: true, result });
  }),
);

const remindBody = z.object({ kind: z.enum(['expired', 'expiring']).optional() });
const NO_PUSH = { recipients: 0, delivered: 0, failed: 0, invalidTokens: [] };

/** Remind users whose package has ended and/or ends within 3 days. */
adminRouter.post(
  '/notifications/remind',
  route(async (req, res) => {
    const { kind } = remindBody.parse(req.body ?? {});
    const expired =
      kind === 'expiring' ? NO_PUSH : await sendNotification({ ...REMINDERS.expired, target: 'expired' });
    const expiring =
      kind === 'expired' ? NO_PUSH : await sendNotification({ ...REMINDERS.expiring, target: 'expiring' });
    res.json({ ok: true, expired, expiring });
  }),
);

// ───────────────────────────── Settings ─────────────────────────────

const settingsBody = z.object({
  maintenance: z.object({ enabled: z.boolean(), message: z.string().trim().max(300) }),
  appUpdate: z.object({
    latestVersion: z.string().trim().regex(/^\d+(\.\d+){0,2}$/, 'Use a version like 1.2.0'),
    minVersion: z.string().trim().regex(/^\d+(\.\d+){0,2}$/, 'Use a version like 1.0.0'),
    force: z.boolean(),
    message: z.string().trim().max(300),
    url: z.string().trim().url().or(z.literal('')),
  }),
  supportWhatsApp: z.string().trim().regex(/^255\d{9}$/, 'Use 255XXXXXXXXX'),
});

async function settingsPayload() {
  const [maintenance, appUpdate, support, refresh] = await Promise.all([
    getSetting('maintenance'),
    getSetting('app_update'),
    getSetting('support'),
    getSetting('refresh'),
  ]);
  return {
    maintenance,
    appUpdate,
    supportWhatsApp: support.whatsapp,
    refreshToken: refresh.token,
    services: {
      sonicPesa: sonicPesaConfigured(),
      sonicPesaWebhook: webhookSigningSecret().length > 0,
      push: pushConfigured(),
    },
  };
}

adminRouter.get(
  '/settings',
  route(async (_req, res) => {
    res.json({ ok: true, settings: await settingsPayload() });
  }),
);

adminRouter.put(
  '/settings',
  route(async (req, res) => {
    const s = settingsBody.partial().parse(req.body);
    if (s.maintenance) await setSetting('maintenance', s.maintenance);
    if (s.appUpdate) await setSetting('app_update', s.appUpdate);
    if (s.supportWhatsApp) await setSetting('support', { whatsapp: s.supportWhatsApp });
    res.json({ ok: true, settings: await settingsPayload() });
  }),
);

/** Make every user app restart and reload its data. */
adminRouter.post(
  '/refresh-apps',
  route(async (_req, res) => {
    const token = await bumpRefreshToken();
    let pushed = false;
    if (pushConfigured()) {
      try {
        await pushRefreshCommand();
        pushed = true;
      } catch (err) {
        logger.warn({ err }, 'refresh_push_failed');
      }
    }
    res.json({ ok: true, refreshToken: token, pushed });
  }),
);

// ───────────────────────────── Danger zone ─────────────────────────────

/** Ends every active package. Requires typing DOWNGRADE in the admin app. */
adminRouter.post(
  '/danger/downgrade-all',
  route(async (req, res) => {
    z.object({ confirm: z.literal('DOWNGRADE') }).parse(req.body);
    const rows = await query(
      `UPDATE users SET plan_id = NULL, expires_at = NULL, period_days = 0
       WHERE expires_at > now() RETURNING id`,
    );
    await bumpRefreshToken();
    logger.warn({ count: rows.length }, 'danger_downgrade_all');
    res.json({ ok: true, downgraded: rows.length });
  }),
);
