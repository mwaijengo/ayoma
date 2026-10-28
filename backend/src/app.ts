import { basename, join, resolve } from 'node:path';

import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import pinoHttp from 'pino-http';

import { env } from './config/env';
import { getPool } from './db/pool';
import { errorHandler, notFound } from './lib/http';
import { logger } from './lib/logger';
import { adminRouter } from './routes/admin';
import { appRouter } from './routes/app';
import { authRouter } from './routes/auth';
import { mediaRouter } from './routes/media';
import { webhookRouter } from './routes/webhooks';

/** `backend/public`, from both `src/` (dev) and `dist/` (production). */
const PUBLIC_DIR = resolve(__dirname, '..', 'public');

export function createApp(): express.Application {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1);
  app.use(helmet());
  app.use(
    cors({
      origin: (origin, cb) => {
        if (!origin || env.corsOrigin === '*') return cb(null, true);
        if (/^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(origin)) return cb(null, true);
        cb(null, env.corsOrigin.split(',').map((o) => o.trim()).includes(origin));
      },
    }),
  );

  // Webhook signatures are computed over the exact raw body.
  app.use('/api/v1/webhooks', express.raw({ type: () => true, limit: '1mb' }), (req, _res, next) => {
    if (Buffer.isBuffer(req.body)) {
      const raw = req.body.toString('utf8');
      (req as express.Request & { rawBody?: string }).rawBody = raw;
      try {
        req.body = raw ? JSON.parse(raw) : {};
      } catch {
        req.body = {};
      }
    }
    next();
  });
  app.use(express.json({ limit: '1mb' }));
  app.use(
    pinoHttp({
      logger,
      autoLogging: { ignore: (req) => req.url === '/api/v1/health' },
    }),
  );

  // AyomaStore: the download website and the APK files.
  app.use(
    '/downloads',
    express.static(join(PUBLIC_DIR, 'downloads'), {
      maxAge: '5m',
      setHeaders: (res, file) => {
        if (!file.endsWith('.apk')) return;
        res.setHeader('Content-Type', 'application/vnd.android.package-archive');
        res.setHeader('Content-Disposition', `attachment; filename="${basename(file)}"`);
      },
    }),
  );
  // Revalidate on every visit so store updates show up immediately.
  app.use(express.static(join(PUBLIC_DIR, 'store'), {
    setHeaders: (res) => res.setHeader('Cache-Control', 'no-cache'),
  }));

  app.get('/api/v1/health', async (_req, res) => {
    try {
      await getPool().query('SELECT 1');
      res.json({ ok: true, db: true, time: new Date() });
    } catch {
      res.status(503).json({ ok: false, db: false });
    }
  });

  app.use('/api/v1/auth', authRouter);
  app.use('/api/v1/app', appRouter);
  app.use('/api/v1/admin', adminRouter);
  app.use('/api/v1/media', mediaRouter);
  app.use('/api/v1/webhooks', webhookRouter);

  app.use(notFound);
  app.use(errorHandler);
  return app;
}
