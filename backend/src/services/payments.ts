import { query, queryOne, transaction } from '../db/pool';
import { HttpError } from '../lib/http';
import { logger } from '../lib/logger';
import type { PaymentRow, PlanRow, UserRow } from './serializers';
import * as sonic from './sonicPesa';
import { activateSubscription } from './subscriptions';

/**
 * Marks a payment paid and adds its days to the user. Safe to call more than
 * once (webhook + polling): only the first call activates.
 */
export async function markPaid(paymentId: number): Promise<PaymentRow | null> {
  return transaction(async (client) => {
    const res = await client.query<PaymentRow>(
      `UPDATE payments SET status = 'paid', paid_at = now()
       WHERE id = $1 AND status <> 'paid' RETURNING *`,
      [paymentId],
    );
    const payment = res.rows[0];
    if (!payment) return null;
    await activateSubscription(client, payment.user_id, payment.plan_id, payment.days);
    logger.info({ paymentId, userId: payment.user_id }, 'payment_paid');
    return payment;
  });
}

export async function markFailed(paymentId: number, message: string): Promise<void> {
  await query(
    `UPDATE payments SET status = 'failed', message = $2 WHERE id = $1 AND status = 'pending'`,
    [paymentId, message],
  );
}

export async function getActivePlan(planId: string): Promise<PlanRow> {
  const plan = await queryOne<PlanRow>('SELECT * FROM plans WHERE id = $1 AND active', [planId]);
  if (!plan) throw new HttpError(404, 'Kifurushi hakipatikani', 'PLAN_NOT_FOUND');
  return plan;
}

export async function startMobilePayment(
  user: UserRow,
  input: { planId: string; name: string; phone: string },
): Promise<PaymentRow> {
  if (!sonic.sonicPesaConfigured()) {
    throw new HttpError(
      503,
      'Malipo hayapatikani kwa sasa. Wasiliana nasi kwa WhatsApp.',
      'PAYMENTS_DISABLED',
    );
  }
  const phone = sonic.parseTzPhone(input.phone);
  if (!phone.ok) throw new HttpError(400, phone.message, 'INVALID_PHONE');
  const plan = await getActivePlan(input.planId);

  // A second push while the first USSD is open makes every network say "session busy".
  const open = await queryOne<PaymentRow>(
    `SELECT * FROM payments
     WHERE user_id = $1 AND status = 'pending' AND phone = $2 AND plan_id = $3
       AND created_at > now() - interval '3 minutes'
     ORDER BY id DESC LIMIT 1`,
    [user.id, phone.local, plan.id],
  );
  if (open?.order_id) return open;
  if (open && Date.now() - new Date(open.created_at).getTime() < 45_000) {
    throw new HttpError(
      409,
      `Ombi la PIN ya ${phone.wallet} tayari limetumwa. Angalia simu yako, usitume ombi jingine.`,
      'USSD_BUSY',
    );
  }

  await query('UPDATE users SET name = $2, phone = $3 WHERE id = $1', [user.id, input.name, phone.local]);

  const payment = await queryOne<PaymentRow>(
    `INSERT INTO payments (user_id, plan_id, plan_name, days, amount_tzs, phone, payer_name, provider)
     VALUES ($1, $2, $3, $4, $5, $6, $7, 'sonicpesa') RETURNING *`,
    [user.id, plan.id, plan.name, plan.days, plan.price_tzs, phone.local, input.name],
  );
  if (!payment) throw new Error('payment insert failed');

  const order = await sonic.createOrder({
    phone: phone.local,
    name: input.name,
    email: `user${user.id}@ayoma.app`,
    amountTzs: plan.price_tzs,
    reference: `ayoma-${payment.id}`,
    planId: plan.id,
  });

  if (!order.ok) {
    const maybeSent = /limetumwa|angalia simu/i.test(order.message);
    if (maybeSent) {
      const waiting = await queryOne<PaymentRow>(
        `UPDATE payments SET message = $2 WHERE id = $1 RETURNING *`,
        [payment.id, `Angalia simu yako na uweke PIN ya ${phone.wallet}.`],
      );
      return waiting ?? payment;
    }
    await markFailed(payment.id, order.message);
    throw new HttpError(400, order.message, 'PAYMENT_START_FAILED');
  }

  const updated = await queryOne<PaymentRow>(
    `UPDATE payments SET order_id = $2, message = $3 WHERE id = $1 RETURNING *`,
    [payment.id, order.orderId, `Weka PIN ya ${phone.wallet} kwenye simu yako.`],
  );
  return updated ?? payment;
}

/** Asks SonicPesa about a pending payment and settles it if it changed. */
export async function refreshPayment(payment: PaymentRow): Promise<PaymentRow> {
  if (payment.status !== 'pending' || !payment.order_id || !sonic.sonicPesaConfigured()) {
    return payment;
  }
  const status = await sonic.orderStatus(payment.order_id);
  if (status === 'paid') await markPaid(payment.id);
  if (status === 'failed') await markFailed(payment.id, 'Malipo hayakukamilika. Jaribu tena.');
  return (await queryOne<PaymentRow>('SELECT * FROM payments WHERE id = $1', [payment.id])) ?? payment;
}

/** Admin records a payment taken outside the app (cash, manual transfer) or a free grant. */
export async function recordAdminPayment(input: {
  userId: number;
  planId: string;
  days?: number;
  amountTzs?: number;
  phone?: string;
  note?: string;
  grant: boolean;
}): Promise<PaymentRow> {
  const plan = await queryOne<PlanRow>('SELECT * FROM plans WHERE id = $1', [input.planId]);
  if (!plan) throw new HttpError(404, 'Plan not found', 'PLAN_NOT_FOUND');
  const days = input.days ?? plan.days;
  const amount = input.grant ? 0 : (input.amountTzs ?? plan.price_tzs);

  return transaction(async (client) => {
    const res = await client.query<PaymentRow>(
      `INSERT INTO payments
         (user_id, plan_id, plan_name, days, amount_tzs, phone, provider, status, note, message, paid_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, 'paid', $8, '', now()) RETURNING *`,
      [
        input.userId,
        plan.id,
        plan.name,
        days,
        amount,
        input.phone ?? '',
        input.grant ? 'admin_grant' : 'manual',
        input.note ?? '',
      ],
    );
    const payment = res.rows[0]!;
    await activateSubscription(client, input.userId, plan.id, days);
    return payment;
  });
}
