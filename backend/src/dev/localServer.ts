/**
 * Local development without installing Postgres: starts an embedded Postgres
 * in `.local-pg/` and then the API. Never used in production.
 */
import path from 'node:path';
import fs from 'node:fs';

const PG_PORT = 54329;
const dataDir = path.resolve(__dirname, '../../.local-pg');

async function main(): Promise<void> {
  const { default: EmbeddedPostgres } = await import('embedded-postgres');
  const pg = new EmbeddedPostgres({
    databaseDir: dataDir,
    user: 'ayoma',
    password: 'ayoma',
    port: PG_PORT,
    persistent: true,
    initdbFlags: ['--encoding=UTF8', '--locale=C'],
  });
  const fresh = !fs.existsSync(path.join(dataDir, 'PG_VERSION'));
  if (fresh) await pg.initialise();
  await pg.start();
  if (fresh) await pg.createDatabase('ayoma');

  process.env.DATABASE_URL = `postgresql://ayoma:ayoma@localhost:${PG_PORT}/ayoma`;
  process.env.JWT_SECRET ||= 'local-dev-jwt-secret-change-me';
  process.env.ADMIN_PASSWORD ||= 'ayoma-admin';

  const stop = async () => {
    await pg.stop();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);

  // Imported after DATABASE_URL is set, because env is read at import time.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { start } = require('../index') as { start: () => Promise<void> };
  await start();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
