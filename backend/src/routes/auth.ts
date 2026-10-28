import { Router } from 'express';
import jwt from 'jsonwebtoken';
import { z } from 'zod';

import { ADMIN_SESSION_HOURS, env } from '../config/env';
import { HttpError, route } from '../lib/http';
import { safeEqualHex, sha256 } from '../middleware/auth';

export const authRouter = Router();

const failedAttempts = new Map<string, { count: number; until: number }>();
const MAX_ATTEMPTS = 5;
const LOCK_MS = 5 * 60 * 1000;

/** Admin logs in with the secret password only. The token lasts 24 hours. */
authRouter.post(
  '/admin-login',
  route(async (req, res) => {
    if (!env.adminPassword || !env.jwtSecret) {
      throw new HttpError(
        503,
        'Admin login is not configured: set JWT_SECRET and ADMIN_PASSWORD on the server',
        'ADMIN_DISABLED',
      );
    }
    const ip = req.ip ?? 'unknown';
    const lock = failedAttempts.get(ip);
    if (lock && lock.count >= MAX_ATTEMPTS && lock.until > Date.now()) {
      throw new HttpError(429, 'Too many wrong passwords. Try again in 5 minutes.', 'LOCKED');
    }

    const { password } = z.object({ password: z.string().min(1) }).parse(req.body);
    if (!safeEqualHex(sha256(password), sha256(env.adminPassword))) {
      const count = (lock && lock.until > Date.now() ? lock.count : 0) + 1;
      failedAttempts.set(ip, { count, until: Date.now() + LOCK_MS });
      throw new HttpError(401, 'Wrong password', 'WRONG_PASSWORD');
    }
    failedAttempts.delete(ip);

    const expiresAt = new Date(Date.now() + ADMIN_SESSION_HOURS * 60 * 60 * 1000);
    const token = jwt.sign({ sub: 'admin', role: 'admin' }, env.jwtSecret, {
      expiresIn: `${ADMIN_SESSION_HOURS}h`,
    });
    res.json({ ok: true, token, expiresAt });
  }),
);
