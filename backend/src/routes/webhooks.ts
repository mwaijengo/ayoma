import { Router, type Request } from 'express';

import { env } from '../config/env';
import { queryOne } from '../db/pool';
import { route } from '../lib/http';
import { logger } from '../lib/logger';
import { markFailed, markPaid, refreshPayment } from '../services/payments';
import type { PaymentRow } from '../services/serializers';
import { parseWebhook, verifyWebhook } from '../services/sonicPesa';

export const webhookRouter = Router();

type RawRequest = Request & { rawBody?: string };

webhookRouter.post(
  '/sonicpesa',
  route(async (req, res) => {
    const raw = (req as RawRequest).rawBody ?? JSON.stringify(req.body ?? {});
    const signature =
      req.header('x-sonicpesa-signature') ?? req.header('x-webhook-signature') ?? req.header('x-signature');
    const signed = verifyWebhook(raw, signature);

    const { orderId, status } = parseWebhook((req.body ?? {}) as Record<string, unknown>);
    if (!orderId) {
      res.status(400).json({ ok: false, error: 'Missing order id' });
      return;
    }
    const payment = await queryOne<PaymentRow>('SELECT * FROM payments WHERE order_id = $1', [orderId]);
    if (!payment) {
      logger.warn({ orderId }, 'webhook_unknown_order');
      res.json({ ok: true, ignored: true });
      return;
    }

    if (env.sonicPesaWebhookSecret) {
      if (!signed) {
        res.status(401).json({ ok: false, error: 'Invalid signature' });
        return;
      }
      if (status === 'paid') await markPaid(payment.id);
      if (status === 'failed') await markFailed(payment.id, 'Malipo hayakukamilika. Jaribu tena.');
    } else {
      // Without a webhook secret, never trust the body: ask SonicPesa directly.
      await refreshPayment(payment);
    }
    res.json({ ok: true });
  }),
);
