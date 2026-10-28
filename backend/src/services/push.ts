import { readFileSync } from 'node:fs';

import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging, type AndroidConfig, type MulticastMessage } from 'firebase-admin/messaging';

import { env } from '../config/env';
import { HttpError } from '../lib/http';
import { logger } from '../lib/logger';

type ServiceAccount = { project_id?: string; client_email?: string; private_key?: string };

function loadServiceAccount(): ServiceAccount | null {
  if (env.fcmServiceAccountJson) return JSON.parse(env.fcmServiceAccountJson) as ServiceAccount;
  if (env.fcmServiceAccountPath) {
    return JSON.parse(readFileSync(env.fcmServiceAccountPath, 'utf8')) as ServiceAccount;
  }
  return null;
}

export function pushConfigured(): boolean {
  return Boolean(env.fcmServiceAccountJson || env.fcmServiceAccountPath);
}

function ensureApp(): void {
  if (getApps().length > 0) return;
  const sa = loadServiceAccount();
  if (!sa?.project_id || !sa.client_email || !sa.private_key) {
    throw new HttpError(
      503,
      'Push notifications are not configured. Set FCM_SERVICE_ACCOUNT_JSON on the server.',
      'PUSH_DISABLED',
    );
  }
  initializeApp({
    credential: cert({
      projectId: sa.project_id,
      clientEmail: sa.client_email,
      privateKey: sa.private_key.replace(/\\n/g, '\n'),
    }),
  });
}

/** Firebase keeps undelivered messages up to 4 weeks for phones that are off or offline. */
const MAX_TTL_MS = 28 * 24 * 60 * 60 * 1000;

const ANDROID_ALERT: AndroidConfig = {
  priority: 'high', // wakes phones from Doze / deep sleep
  ttl: MAX_TTL_MS,
  notification: {
    channelId: 'uhurumax_alerts',
    defaultSound: true,
    defaultVibrateTimings: true,
    priority: 'max',
    visibility: 'public',
  },
};

const ANDROID_SILENT: AndroidConfig = { priority: 'high', ttl: 60 * 60 * 1000 };

export type PushResult = { recipients: number; delivered: number; failed: number; invalidTokens: string[] };

const BATCH_SIZE = 500; // FCM multicast limit
const PARALLEL_BATCHES = 20;
const RETRY_DELAY_MS = 2000;

const DEAD_TOKEN_CODES = ['registration-token-not-registered', 'invalid-registration-token', 'invalid-argument'];
const RETRYABLE_CODES = ['unavailable', 'internal-error', 'server-unavailable', 'unknown-error', 'message-rate-exceeded'];

type Outcome = { delivered: number; dead: string[]; retry: string[]; error?: unknown };

/**
 * Sends to device tokens in batches of 500, many batches at once so a large
 * audience is reached together. Temporary Firebase errors are retried once.
 * A message without [title] is data-only, e.g. a silent "refresh" command.
 */
export async function sendToTokens(
  tokens: string[],
  message: { title?: string; body?: string; data?: Record<string, string> },
): Promise<PushResult> {
  const unique = [...new Set(tokens.filter(Boolean))];
  const result: PushResult = { recipients: unique.length, delivered: 0, failed: 0, invalidTokens: [] };
  if (unique.length === 0) return result;
  ensureApp();

  const payload = {
    notification: message.title ? { title: message.title, body: message.body ?? '' } : undefined,
    data: { source: 'ayoma_admin', ...(message.data ?? {}) },
    android: message.title ? ANDROID_ALERT : ANDROID_SILENT,
  };

  const first = await sendAll(unique, payload);
  let delivered = first.delivered;
  const dead = [...first.dead];
  let failedTokens = first.retry;

  if (failedTokens.length > 0) {
    await new Promise((r) => setTimeout(r, RETRY_DELAY_MS));
    const second = await sendAll(failedTokens, payload);
    delivered += second.delivered;
    dead.push(...second.dead);
    failedTokens = second.retry;
  }

  result.delivered = delivered;
  result.invalidTokens = dead;
  result.failed = unique.length - delivered;

  if (delivered === 0 && first.error) {
    const reason = first.error instanceof Error ? first.error.message : String(first.error);
    throw new HttpError(502, `Firebase rejected the notification: ${reason}`, 'PUSH_FAILED');
  }
  logger.info({ ...result, invalidTokens: dead.length, unresolved: failedTokens.length }, 'push_sent');
  return result;
}

async function sendAll(
  tokens: string[],
  payload: Omit<MulticastMessage, 'tokens'>,
): Promise<Outcome> {
  const out: Outcome = { delivered: 0, dead: [], retry: [] };
  const batches: string[][] = [];
  for (let i = 0; i < tokens.length; i += BATCH_SIZE) batches.push(tokens.slice(i, i + BATCH_SIZE));

  const sendBatch = async (batch: string[]) => {
    try {
      const res = await getMessaging().sendEachForMulticast({ ...payload, tokens: batch });
      out.delivered += res.successCount;
      res.responses.forEach((r, idx) => {
        if (r.success) return;
        const code = r.error?.code ?? '';
        if (DEAD_TOKEN_CODES.some((c) => code.endsWith(c))) out.dead.push(batch[idx]!);
        else if (RETRYABLE_CODES.some((c) => code.endsWith(c))) out.retry.push(batch[idx]!);
      });
    } catch (err) {
      out.error ??= err;
      out.retry.push(...batch);
      logger.error({ err, size: batch.length }, 'push_batch_failed');
    }
  };

  for (let i = 0; i < batches.length; i += PARALLEL_BATCHES) {
    await Promise.all(batches.slice(i, i + PARALLEL_BATCHES).map(sendBatch));
  }
  return out;
}