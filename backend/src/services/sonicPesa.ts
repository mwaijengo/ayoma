import { createHmac, timingSafeEqual } from 'crypto';

import { env } from '../config/env';
import { logger } from '../lib/logger';

const API_BASE = 'https://api.sonicpesa.com/api/v1';
const TIMEOUT_MS = 16_000;

const PAID_STATUSES = new Set([
  'SUCCESS',
  'SUCCESSFUL',
  'SUCCEEDED',
  'COMPLETED',
  'COMPLETE',
  'PAID',
  'APPROVED',
  'CONFIRMED',
  'SETTLED',
]);
const FAILED_STATUSES = new Set(['FAILED', 'FAILURE', 'CANCELLED', 'CANCELED', 'REJECTED', 'EXPIRED']);

export function sonicPesaConfigured(): boolean {
  return env.sonicPesaApiKey.length > 0;
}

function headers(): Record<string, string> {
  const h: Record<string, string> = {
    'Content-Type': 'application/json',
    Accept: 'application/json',
    'X-API-KEY': env.sonicPesaApiKey,
  };
  if (env.sonicPesaSecretKey) {
    // Sonic accepts either header name depending on the dashboard version.
    h['X-SECRET-KEY'] = env.sonicPesaSecretKey;
    h['X-API-SECRET'] = env.sonicPesaSecretKey;
  }
  return h;
}

async function post(path: string, body: unknown): Promise<{ ok: boolean; data: Record<string, unknown> }> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(`${API_BASE}/${path}`, {
      method: 'POST',
      headers: headers(),
      body: JSON.stringify(body),
      signal: ctrl.signal,
    });
    const text = await res.text();
    let data: Record<string, unknown>;
    try {
      data = (JSON.parse(text) as Record<string, unknown>) ?? {};
    } catch {
      data = { status: 'error', message: text.slice(0, 200) };
    }
    return { ok: res.ok, data };
  } finally {
    clearTimeout(timer);
  }
}

function nested(data: Record<string, unknown>): Record<string, unknown> {
  const d = data.data;
  if (Array.isArray(d) && d[0] && typeof d[0] === 'object') return d[0] as Record<string, unknown>;
  if (d && typeof d === 'object') return d as Record<string, unknown>;
  return {};
}

function message(data: Record<string, unknown>): string {
  const row = nested(data);
  for (const v of [data.message, data.error, data.detail, row.message, row.error]) {
    const s = String(v ?? '').trim();
    if (s) return s;
  }
  return '';
}

function orderIdOf(data: Record<string, unknown>): string {
  const row = nested(data);
  return String(row.order_id ?? row.orderId ?? data.order_id ?? data.orderId ?? '').trim();
}

function statusOf(data: Record<string, unknown>): string {
  const row = nested(data);
  for (const v of [
    row.payment_status,
    row.paymentStatus,
    row.transaction_status,
    row.order_status,
    row.status,
    data.payment_status,
    data.status,
  ]) {
    if (v != null && typeof v !== 'object') {
      const s = String(v).toUpperCase().trim();
      if (s) return s;
    }
  }
  return '';
}

/** "0712345678" → "255712345678", which SonicPesa requires for every wallet. */
export function toIntl255(localPhone: string): string {
  const digits = localPhone.replace(/\D/g, '');
  if (digits.startsWith('255')) return digits;
  if (digits.startsWith('0')) return `255${digits.slice(1)}`;
  return `255${digits}`;
}

export type CreateOrderResult =
  | { ok: true; orderId: string; message: string }
  | { ok: false; message: string };

export async function createOrder(input: {
  phone: string;
  name: string;
  email: string;
  amountTzs: number;
  reference: string;
  planId: string;
}): Promise<CreateOrderResult> {
  try {
    const { ok, data } = await post('payment/create_order', {
      buyer_email: input.email,
      buyer_name: input.name,
      buyer_phone: toIntl255(input.phone),
      amount: Math.max(1, Math.trunc(input.amountTzs)),
      currency: 'TZS',
      metadata: { external_id: input.reference, plan_id: input.planId },
    });
    const orderId = orderIdOf(data);
    const status = String(data.status ?? '').toLowerCase();
    if (orderId && ok && status !== 'error' && status !== 'failed') {
      logger.info({ orderId }, 'sonic_order_created');
      return { ok: true, orderId, message: message(data) };
    }
    logger.warn({ data }, 'sonic_order_failed');
    return {
      ok: false,
      message: friendlyError(message(data)),
    };
  } catch (err) {
    const aborted = /abort|timeout/i.test(String(err));
    logger.warn({ err }, 'sonic_order_exception');
    return {
      ok: false,
      message: aborted
        ? 'Ombi la PIN linaweza kuwa limetumwa kwenye simu yako. Angalia simu yako.'
        : 'Huduma ya malipo haipatikani kwa sasa. Jaribu tena baada ya muda mfupi.',
    };
  }
}

function friendlyError(raw: string): string {
  const m = raw.toLowerCase();
  if (/ongoing ussd|session busy/.test(m)) {
    return 'Simu yako ina USSD nyingine inayoendelea. Funga dirisha hilo, subiri sekunde 30, kisha jaribu tena.';
  }
  if (/invalid phone|invalid msisdn|wrong number/.test(m)) {
    return 'Namba ya simu si sahihi. Tumia namba ya M-Pesa, Mixx by Yas, Airtel Money au Halopesa.';
  }
  return raw || 'Malipo hayakuanza. Jaribu tena baada ya muda mfupi.';
}

export type OrderStatus = 'paid' | 'failed' | 'pending';

export async function orderStatus(orderId: string): Promise<OrderStatus> {
  try {
    const { data } = await post('payment/order_status', { order_id: orderId });
    const s = statusOf(data);
    if (PAID_STATUSES.has(s)) return 'paid';
    if (FAILED_STATUSES.has(s)) return 'failed';
    return 'pending';
  } catch (err) {
    logger.warn({ err, orderId }, 'sonic_status_exception');
    return 'pending';
  }
}

function safeEqual(a: string, b: string): boolean {
  const x = Buffer.from(a.trim().toLowerCase().replace(/^sha256=/, ''), 'utf8');
  const y = Buffer.from(b.trim().toLowerCase(), 'utf8');
  return x.length === y.length && timingSafeEqual(x, y);
}

export function verifyWebhook(rawBody: string, signature: string | undefined): boolean {
  if (!env.sonicPesaWebhookSecret || !signature) return false;
  const expected = createHmac('sha256', env.sonicPesaWebhookSecret).update(rawBody, 'utf8').digest('hex');
  return safeEqual(signature, expected);
}

export function parseWebhook(payload: Record<string, unknown>): { orderId: string; status: OrderStatus } {
  const row = nested(payload);
  const orderId = String(
    payload.order_id ?? payload.orderId ?? row.order_id ?? row.orderId ?? payload.reference ?? '',
  ).trim();
  const s = statusOf(payload);
  const event = String(payload.event ?? payload.type ?? '').toLowerCase();
  let status: OrderStatus = 'pending';
  if (PAID_STATUSES.has(s) || /\.(success|completed|paid)$/.test(event)) status = 'paid';
  else if (FAILED_STATUSES.has(s) || /\.(failed|cancelled)$/.test(event)) status = 'failed';
  return { orderId, status };
}
