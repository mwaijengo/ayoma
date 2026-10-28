import { query } from '../db/pool';
import { HttpError } from '../lib/http';
import { pushConfigured, sendToTokens, type PushResult } from './push';

export const NOTIFICATION_TARGETS = ['all', 'premium', 'free', 'expired', 'expiring', 'user'] as const;
export type NotificationTarget = (typeof NOTIFICATION_TARGETS)[number];

const TARGET_SQL: Record<Exclude<NotificationTarget, 'user'>, string> = {
  all: 'true',
  premium: 'expires_at > now()',
  free: '(expires_at IS NULL OR expires_at <= now())',
  expired: 'expires_at <= now()',
  expiring: "expires_at > now() AND expires_at <= now() + interval '3 days'",
};

async function tokensFor(target: NotificationTarget, userId?: number): Promise<string[]> {
  if (target === 'user') {
    if (!userId) throw new HttpError(400, 'userId is required', 'VALIDATION');
    const rows = await query<{ fcm_token: string }>(
      `SELECT fcm_token FROM users WHERE id = $1 AND fcm_token <> ''`,
      [userId],
    );
    return rows.map((r) => r.fcm_token);
  }
  const rows = await query<{ fcm_token: string }>(
    `SELECT fcm_token FROM users WHERE fcm_token <> '' AND NOT blocked AND ${TARGET_SQL[target]}`,
  );
  return rows.map((r) => r.fcm_token);
}

async function forgetTokens(tokens: string[]): Promise<void> {
  if (tokens.length === 0) return;
  await query(`UPDATE users SET fcm_token = '' WHERE fcm_token = ANY($1)`, [tokens]);
}

export async function sendNotification(input: {
  title: string;
  body: string;
  target: NotificationTarget;
  userId?: number;
}): Promise<PushResult> {
  const tokens = await tokensFor(input.target, input.userId);
  const result = await sendToTokens(tokens, {
    title: input.title,
    body: input.body,
    data: { type: 'notification' },
  });
  await forgetTokens(result.invalidTokens);
  await query(
    `INSERT INTO notifications (title, body, target, recipients, delivered, failed)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [
      input.title,
      input.body,
      input.target === 'user' ? `user:${input.userId}` : input.target,
      result.recipients,
      result.delivered,
      result.failed,
    ],
  );
  return result;
}

export const REMINDERS = {
  expired: {
    title: 'Kifurushi chako kimeisha',
    body: 'Lipia sasa uendelee kutazama chaneli zote za AyomaMax.',
  },
  expiring: {
    title: 'Kifurushi chako kinakaribia kuisha',
    body: 'Ongezea siku za matumizi sasa kabla hujazimiwa huduma.',
  },
};

const AUTO_REMINDERS = {
  expiring: {
    column: 'reminded_expiring_for',
    window: "expires_at > now() AND expires_at <= now() + interval '1 day'",
  },
  expired: {
    column: 'reminded_expired_for',
    window: "expires_at <= now() AND expires_at > now() - interval '2 days'",
  },
} as const;

/**
 * Reminds each user once when their package is about to end and once right
 * after it ends. Users are claimed with a single UPDATE so overlapping runs
 * never remind anyone twice.
 */
export async function runAutoReminders(): Promise<void> {
  if (!pushConfigured()) return;
  for (const kind of ['expiring', 'expired'] as const) {
    const { column, window } = AUTO_REMINDERS[kind];
    const rows = await query<{ fcm_token: string }>(
      `UPDATE users SET ${column} = expires_at
       WHERE fcm_token <> '' AND NOT blocked AND ${window} AND ${column} IS DISTINCT FROM expires_at
       RETURNING fcm_token`,
    );
    if (rows.length === 0) continue;
    const result = await sendToTokens(
      rows.map((r) => r.fcm_token),
      { ...REMINDERS[kind], data: { type: 'reminder' } },
    );
    await forgetTokens(result.invalidTokens);
    await query(
      `INSERT INTO notifications (title, body, target, recipients, delivered, failed)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [REMINDERS[kind].title, REMINDERS[kind].body, `auto:${kind}`, result.recipients, result.delivered, result.failed],
    );
  }
}

/** Silent push telling apps to reload; apps also notice on their next sync. */
export async function pushRefreshCommand(): Promise<void> {
  const rows = await query<{ fcm_token: string }>(`SELECT fcm_token FROM users WHERE fcm_token <> ''`);
  const result = await sendToTokens(
    rows.map((r) => r.fcm_token),
    { data: { type: 'refresh' } },
  );
  await forgetTokens(result.invalidTokens);
}
