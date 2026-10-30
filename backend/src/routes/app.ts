import { randomBytes } from 'crypto';

import { Router } from 'express';
import { z } from 'zod';

import { query, queryOne } from '../db/pool';
import { HttpError, intParam, route } from '../lib/http';
import { requireDevice, safeEqualHex, sha256, type DeviceRequest } from '../middleware/auth';
import { getActivePlan, refreshPayment, startMobilePayment } from '../services/payments';
import {
  appPayment,
  appUser,
  playbackConfig,
  publicChannel,
  publicPlan,
  publicSlide,
  type ChannelRow,
  type PaymentRow,
  type PlanRow,
  type SlideRow,
  type UserRow,
} from '../services/serializers';
import { getAppConfig } from '../services/settings';
import { isSubscribed } from '../services/subscriptions';

export const appRouter = Router();

const deviceInfo = z.object({
  platform: z.string().max(20).optional(),
  appVersion: z.string().max(20).optional(),
});

/**
 * First launch: the app sends its device ID and receives a secret it keeps.
 * An existing device can only re-register with its current secret.
 */
appRouter.post(
  '/register',
  route(async (req, res) => {
    const body = deviceInfo
      .extend({
        deviceId: z.string().regex(/^[A-Za-z0-9-]{6,40}$/),
        secret: z.string().max(128).optional(),
      })
      .parse(req.body);

    const existing = await queryOne<UserRow & { secret_hash: string }>(
      'SELECT * FROM users WHERE device_id = $1',
      [body.deviceId],
    );
    if (existing) {
      if (!body.secret || !safeEqualHex(sha256(body.secret), existing.secret_hash)) {
        throw new HttpError(409, 'Device already registered', 'DEVICE_EXISTS');
      }
      res.json({ ok: true, secret: body.secret, user: appUser(existing) });
      return;
    }

    const secret = randomBytes(32).toString('hex');
    const user = await queryOne<UserRow>(
      `INSERT INTO users (device_id, secret_hash, platform, app_version)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [body.deviceId, sha256(secret), body.platform ?? '', body.appVersion ?? ''],
    );
    res.status(201).json({ ok: true, secret, user: appUser(user!) });
  }),
);

appRouter.use(requireDevice);

/** Everything the app needs on start, on resume and on its periodic sync. */
appRouter.get(
  '/bootstrap',
  route(async (req, res) => {
    const { user } = req as DeviceRequest;
    const info = deviceInfo.parse({
      platform: req.header('x-platform') ?? undefined,
      appVersion: req.header('x-app-version') ?? undefined,
    });
    await query(
      `UPDATE users SET last_seen_at = now(),
         platform = COALESCE($2, platform), app_version = COALESCE($3, app_version)
       WHERE id = $1`,
      [user.id, info.platform ?? null, info.appVersion ?? null],
    );

    const [plans, channels, slides, config] = await Promise.all([
      query<PlanRow>('SELECT * FROM plans WHERE active ORDER BY sort_order, price_tzs'),
      query<ChannelRow>('SELECT * FROM channels WHERE active ORDER BY sort_order, id'),
      query<SlideRow>('SELECT * FROM slides WHERE active ORDER BY sort_order, id'),
      getAppConfig(),
    ]);

    res.json({
      ok: true,
      serverTime: new Date(),
      user: appUser(user),
      plans: plans.map(publicPlan),
      channels: channels.map(publicChannel),
      slides: slides.map(publicSlide),
      config,
    });
  }),
);

appRouter.post(
  '/push-token',
  route(async (req, res) => {
    const { user } = req as DeviceRequest;
    const { token } = z.object({ token: z.string().max(4096) }).parse(req.body);
    await query('UPDATE users SET fcm_token = $2 WHERE id = $1', [user.id, token]);
    res.json({ ok: true });
  }),
);

/** Stream URL, DRM keys and headers, only for users allowed to watch. */
appRouter.get(
  '/channels/:id/playback',
  route(async (req, res) => {
    const { user } = req as DeviceRequest;
    if (user.blocked) throw new HttpError(403, 'Akaunti hii imezuiwa.', 'BLOCKED');
    const channel = await queryOne<ChannelRow>('SELECT * FROM channels WHERE id = $1 AND active', [
      intParam(req, 'id'),
    ]);
    if (!channel) throw new HttpError(404, 'Chaneli haipatikani', 'CHANNEL_NOT_FOUND');
    if (channel.premium && !isSubscribed(user)) {
      throw new HttpError(402, 'Lipia kifurushi kutazama chaneli hii.', 'SUBSCRIPTION_REQUIRED');
    }
    if (!channel.stream_url) {
      throw new HttpError(503, 'Chaneli hii haipatikani kwa sasa.', 'NO_STREAM');
    }
    res.json({ ok: true, playback: playbackConfig(channel) });
  }),
);

appRouter.post(
  '/payments',
  route(async (req, res) => {
    const { user } = req as DeviceRequest;
    if (user.blocked) throw new HttpError(403, 'Akaunti hii imezuiwa.', 'BLOCKED');
    const body = z
      .object({
        planId: z.string().min(1),
        name: z.string().trim().min(3).max(80),
        phone: z.string().trim().min(9).max(20),
      })
      .parse(req.body);
    await getActivePlan(body.planId);
    const payment = await startMobilePayment(user, body);
    res.status(201).json({ ok: true, payment: appPayment(payment) });
  }),
);

appRouter.get(
  '/payments/:id',
  route(async (req, res) => {
    const { user } = req as DeviceRequest;
    const payment = await queryOne<PaymentRow>(
      'SELECT * FROM payments WHERE id = $1 AND user_id = $2',
      [intParam(req, 'id'), user.id],
    );
    if (!payment) throw new HttpError(404, 'Payment not found', 'PAYMENT_NOT_FOUND');
    const fresh = await refreshPayment(payment);
    const latest = await queryOne<UserRow>('SELECT * FROM users WHERE id = $1', [user.id]);
    res.json({ ok: true, payment: appPayment(fresh), user: appUser(latest!) });
  }),
);
