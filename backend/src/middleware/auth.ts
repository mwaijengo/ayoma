import { createHash, timingSafeEqual } from 'crypto';

import type { NextFunction, Request, Response } from 'express';
import jwt, { type JwtPayload } from 'jsonwebtoken';

import { env } from '../config/env';
import { queryOne } from '../db/pool';
import { HttpError } from '../lib/http';
import type { UserRow } from '../services/serializers';

export function sha256(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

export function safeEqualHex(a: string, b: string): boolean {
  const x = Buffer.from(a, 'hex');
  const y = Buffer.from(b, 'hex');
  return x.length === y.length && x.length > 0 && timingSafeEqual(x, y);
}

export function requireAdmin(req: Request, _res: Response, next: NextFunction): void {
  if (!env.jwtSecret || !env.adminPassword) {
    next(
      new HttpError(503, 'Admin login is not configured: set JWT_SECRET and ADMIN_PASSWORD', 'ADMIN_DISABLED'),
    );
    return;
  }
  const token = req.header('authorization')?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (token) {
    try {
      const decoded = jwt.verify(token, env.jwtSecret) as JwtPayload & { role?: string };
      if (decoded.role === 'admin') {
        next();
        return;
      }
    } catch {
      // Expired or forged: fall through to 401.
    }
  }
  next(new HttpError(401, 'Session expired. Please log in again.', 'UNAUTHORIZED'));
}

export type DeviceRequest = Request & { user: UserRow };

/**
 * User app requests carry `X-Device-Id` and the `X-Device-Secret` issued at
 * registration, so knowing someone's (copyable) device ID is not enough.
 */
export async function requireDevice(req: Request, _res: Response, next: NextFunction): Promise<void> {
  try {
    const deviceId = req.header('x-device-id')?.trim() ?? '';
    const secret = req.header('x-device-secret')?.trim() ?? '';
    if (!deviceId || !secret) throw new HttpError(401, 'Device not registered', 'DEVICE_UNKNOWN');
    const user = await queryOne<UserRow & { secret_hash: string }>(
      'SELECT * FROM users WHERE device_id = $1',
      [deviceId],
    );
    if (!user) throw new HttpError(401, 'Device not registered', 'DEVICE_UNKNOWN');
    if (!safeEqualHex(sha256(secret), user.secret_hash)) {
      throw new HttpError(401, 'Device secret mismatch', 'DEVICE_SECRET');
    }
    (req as DeviceRequest).user = user;
    next();
  } catch (err) {
    next(err);
  }
}
