import { Router, type Request, type Response } from 'express';

import { queryOne } from '../db/pool';
import { logger } from '../lib/logger';
import { markFailed, markPaid, refreshPayment } from '../services/payments';
import type { PaymentRow } from '../services/serializers';
import { failureMessage, parseWebhook, verifyWebhook, webhookPhone } from '../services/sonicPesa';

export const webhookRouter = Router();

type RawRequest = Request & { rawBody?: string };

/** SonicPesa must get HTTP 200 within 5 seconds, then it stops retrying. */
export async function handleSonicWebhook(req: Request, res: Response): Promise<void> {
  const raw = (req as RawRequest).rawBody ?? JSON.stringify(req.body ?? {});
  const signature =
    req.header('x-sonicpesa-signature') ??
    req.header('x-webhook-signature') ??
    req.header('x-signature') ??
    req.header('x-hub-signature-256');
  const payload = (req.body ?? {}) as Record<string, unknown>;
  const { orderId, status } = parseWebhook(payload);
  const signed = verifyWebhook(raw, signature);

  let payment: PaymentRow | null = null;
  if (orderId) {
    payment = await queryOne<PaymentRow>('SELECT * FROM payments WHERE order_id = $1', [orderId]);
  }
  if (!payment) {
    const phone = webhookPhone(payload);
    if (phone && signed) {
      payment = await queryOne<PaymentRow>(
        `SELECT * FROM payments
         WHERE status = 'pending' AND phone = $1 AND created_at > now() - interval '20 minutes'
         ORDER BY id DESC LIMIT 1`,
        [phone],
      );
      if (payment && orderId && !payment.order_id) {
        await queryOne('UPDATE payments SET order_id = $2 WHERE id = $1 AND order_id = \'\'', [
          payment.id,
          orderId,
        ]);
      }
    }
  }

  if (!payment) {
    logger.warn({ orderId }, 'webhook_unknown_order');
    res.json({ ok: true, ignored: true });
    return;
  }

  // A valid signature can settle immediately. Otherwise ask SonicPesa, never the raw body.
  if (signed && status === 'paid') await markPaid(payment.id);
  else if (signed && status === 'failed') await markFailed(payment.id, failureMessage(payload));
  else await refreshPayment(payment);

  res.json({ ok: true });
}

webhookRouter.post('/sonicpesa', (req, res, next) => {
  handleSonicWebhook(req, res).catch(next);
});
