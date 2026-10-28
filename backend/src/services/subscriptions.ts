import type { PoolClient } from 'pg';

import { HttpError } from '../lib/http';

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Adds [days] to the user's subscription. An active subscription is extended
 * from its current end, an expired one starts from now.
 */
export async function activateSubscription(
  client: PoolClient,
  userId: number,
  planId: string,
  days: number,
): Promise<{ expiresAt: Date; periodDays: number }> {
  const res = await client.query<{ expires_at: Date | null }>(
    'SELECT expires_at FROM users WHERE id = $1 FOR UPDATE',
    [userId],
  );
  const row = res.rows[0];
  if (!row) throw new HttpError(404, 'User not found', 'USER_NOT_FOUND');

  const now = Date.now();
  const current = row.expires_at ? row.expires_at.getTime() : 0;
  const base = Math.max(current, now);
  const expiresAt = new Date(base + days * DAY_MS);
  const periodDays = Math.ceil((expiresAt.getTime() - now) / DAY_MS);

  await client.query(
    'UPDATE users SET plan_id = $2, expires_at = $3, period_days = $4 WHERE id = $1',
    [userId, planId, expiresAt, periodDays],
  );
  return { expiresAt, periodDays };
}

export type UserStatus = 'premium' | 'expired' | 'free' | 'blocked';

export function userStatus(row: { blocked: boolean; expires_at: Date | null }): UserStatus {
  if (row.blocked) return 'blocked';
  if (!row.expires_at) return 'free';
  return row.expires_at.getTime() > Date.now() ? 'premium' : 'expired';
}

export function isSubscribed(row: { expires_at: Date | null }): boolean {
  return !!row.expires_at && row.expires_at.getTime() > Date.now();
}
