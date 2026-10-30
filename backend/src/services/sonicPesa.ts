import { createHmac, timingSafeEqual } from 'crypto';

import { env } from '../config/env';
import { logger } from '../lib/logger';

const API_BASE = 'https://api.sonicpesa.com/api/v1';
const TIMEOUT_MS = 20_000;

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
/** Still on the phone. Must stay pending, including while USSD is in progress. */
const PENDING_STATUSES = new Set(['PENDING', 'INPROGRESS', 'IN_PROGRESS', 'PROCESSING', 'INITIATED']);
const FAILED_STATUSES = new Set([
  'FAILED',
  'FAILURE',
  'CANCELLED',
  'CANCELED',
  'USERCANCELLED',
  'USER_CANCELLED',
  'REJECTED',
  'EXPIRED',
]);

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

function rawStatus(value: unknown): string {
  if (value == null || typeof value === 'object') return '';
  return String(value).toUpperCase().trim();
}

/**
 * Payment state only. The API envelope uses `"status": "success"` to mean the
 * HTTP call worked, which must not be treated as a paid order.
 */
function statusOf(data: Record<string, unknown>): string {
  const row = nested(data);
  const transaction = data.transaction;
  const tx = transaction && typeof transaction === 'object' ? (transaction as Record<string, unknown>) : {};
  for (const v of [
    row.payment_status,
    row.paymentStatus,
    tx.payment_status,
    data.payment_status,
    row.transaction_status,
    row.order_status,
  ]) {
    const s = rawStatus(v);
    if (s) return s;
  }
  for (const v of [tx.status, row.status]) {
    const s = rawStatus(v);
    if (PAID_STATUSES.has(s) || FAILED_STATUSES.has(s) || PENDING_STATUSES.has(s)) return s;
  }
  return '';
}

/** Vodacom, Airtel, Yas, Halotel and TTCL all use the same 255 prefix. */
const WALLETS: Record<string, string> = {
  '74': 'M-Pesa',
  '75': 'M-Pesa',
  '76': 'M-Pesa',
  '68': 'Airtel Money',
  '69': 'Airtel Money',
  '78': 'Airtel Money',
  '65': 'Mixx by Yas',
  '67': 'Mixx by Yas',
  '71': 'Mixx by Yas',
  '77': 'Mixx by Yas',
  '63': 'Mixx by Yas',
  '64': 'Mixx by Yas',
  '61': 'HaloPesa',
  '62': 'HaloPesa',
  '73': 'TTCL Pesa',
};

export type PhoneResult = { ok: true; local: string; intl: string; wallet: string } | { ok: false; message: string };

/** Accepts 07…, 7…, 255… and +255…, including spaces. */
export function parseTzPhone(input: string): PhoneResult {
  let digits = input.replace(/\D/g, '');
  if (digits.startsWith('255') && digits.length === 12) digits = `0${digits.slice(3)}`;
  else if (digits.length === 9 && /^[67]/.test(digits)) digits = `0${digits}`;
  if (!/^0[67]\d{8}$/.test(digits)) {
    return {
      ok: false,
      message: 'Namba ya simu si sahihi. Tumia namba ya M-Pesa, Mixx by Yas, Airtel Money, HaloPesa au TTCL.',
    };
  }
  const prefix = digits.slice(1, 3);
  return {
    ok: true,
    local: digits,
    intl: `255${digits.slice(1)}`,
    wallet: WALLETS[prefix] ?? 'mtandao wako',
  };
}

/** "0712345678" → "255712345678", which SonicPesa requires for every wallet. */
export function toIntl255(localPhone: string): string {
  const parsed = parseTzPhone(localPhone);
  return parsed.ok ? parsed.intl : localPhone.replace(/\D/g, '');
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
  const phone = parseTzPhone(input.phone);
  if (!phone.ok) return phone;
  const body = {
    buyer_email: input.email,
    buyer_name: input.name,
    buyer_phone: phone.intl,
    amount: Math.max(1, Math.trunc(input.amountTzs)),
    currency: 'TZS',
  };
  let lastMessage = '';
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const { ok, data } = await post('payment/create_order', body);
      const orderId = orderIdOf(data);
      const envelope = String(data.status ?? '').toLowerCase();
      if (orderId && ok && envelope !== 'error' && envelope !== 'failed') {
        logger.info({ orderId, wallet: phone.wallet }, 'sonic_order_created');
        return { ok: true, orderId, message: message(data) };
      }
      lastMessage = friendlyError(message(data));
      logger.warn({ data, attempt }, 'sonic_order_failed');
      if (!/timeout|temporar|unavailable|try again/i.test(lastMessage)) break;
    } catch (err) {
      const aborted = /abort|timeout/i.test(String(err));
      logger.warn({ err, attempt }, 'sonic_order_exception');
      lastMessage = aborted
        ? 'Ombi la PIN linaweza kuwa limetumwa kwenye simu yako. Angalia simu yako.'
        : 'Huduma ya malipo haipatikani kwa sasa. Jaribu tena baada ya muda mfupi.';
      if (!aborted) break;
    }
  }
  return { ok: false, message: lastMessage || 'Malipo hayakuanza. Jaribu tena baada ya muda mfupi.' };
}

function friendlyError(raw: string): string {
  const m = raw.toLowerCase();
  if (/ongoing ussd|session busy/.test(m)) {
    return 'Simu yako ina USSD nyingine inayoendelea. Funga dirisha hilo, subiri sekunde 30, kisha jaribu tena.';
  }
  if (/invalid phone|invalid msisdn|wrong number/.test(m)) {
    return 'Namba ya simu si sahihi. Tumia namba ya M-Pesa, Mixx by Yas, Airtel Money, HaloPesa au TTCL.';
  }
  if (/insufficient|low balance|not enough/.test(m)) {
    return 'Salio halitoshi kwenye simu hii. Ongeza salio kisha jaribu tena.';
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

/** Sonic signs webhooks with the API secret. A separate webhook secret wins when set. */
export function webhookSigningSecret(): string {
  return env.sonicPesaWebhookSecret || env.sonicPesaSecretKey;
}

export function verifyWebhook(rawBody: string, signature: string | undefined): boolean {
  const secret = webhookSigningSecret();
  if (!secret || !signature) return false;
  const expected = createHmac('sha256', secret).update(rawBody, 'utf8').digest('hex');
  return safeEqual(signature, expected);
}

export function parseWebhook(payload: Record<string, unknown>): { orderId: string; status: OrderStatus } {
  const row = nested(payload);
  const orderId = String(payload.order_id ?? payload.orderId ?? row.order_id ?? row.orderId ?? '').trim();
  const s = statusOf(payload);
  const event = String(payload.event ?? payload.type ?? '').toLowerCase();
  let status: OrderStatus = 'pending';
  if (PAID_STATUSES.has(s) || /payment\.(success|completed|paid)$/.test(event)) status = 'paid';
  else if (FAILED_STATUSES.has(s) || /payment\.(failed|cancelled|canceled)$/.test(event)) status = 'failed';
  return { orderId, status };
}

export function webhookPhone(payload: Record<string, unknown>): string {
  const row = nested(payload);
  const raw = String(payload.msisdn ?? payload.phone ?? row.msisdn ?? row.phone ?? '');
  const parsed = parseTzPhone(raw);
  return parsed.ok ? parsed.local : '';
}

export function failureMessage(payload: Record<string, unknown>): string {
  const s = statusOf(payload);
  if (s === 'USERCANCELLED' || s === 'USER_CANCELLED' || s === 'CANCELLED' || s === 'CANCELED') {
    return 'Umekatisha ombi la PIN. Jaribu tena ukiwa tayari kuweka PIN.';
  }
  if (s === 'REJECTED') return 'Mtandao umekataa ombi. Hakikisha namba ina salio, kisha jaribu tena.';
  return 'Malipo hayakukamilika. Jaribu tena.';
}
