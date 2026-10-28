import { createApp } from './app';
import { env } from './config/env';
import { closePool } from './db/pool';
import { migrate } from './db/migrate';
import { logger } from './lib/logger';
import { runAutoReminders } from './services/notifications';

export async function start(): Promise<void> {
  if (!env.jwtSecret || !env.adminPassword) {
    logger.warn('JWT_SECRET or ADMIN_PASSWORD missing: admin login is disabled until both are set');
  }
  await migrate();
  const server = createApp().listen(env.port, '0.0.0.0', () => {
    logger.info({ port: env.port }, 'ayoma_api_listening');
  });

  const shutdown = () => {
    server.close(() => {
      void closePool().finally(() => process.exit(0));
    });
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);

  const remind = () => {
    runAutoReminders().catch((err) => logger.error({ err }, 'auto_reminders_failed'));
  };
  setTimeout(remind, 60_000).unref();
  setInterval(remind, REMINDER_INTERVAL_MS).unref();
}

const REMINDER_INTERVAL_MS = 15 * 60_000;

if (require.main === module) {
  start().catch((err) => {
    logger.error({ err }, 'startup_failed');
    process.exit(1);
  });
}
