import { Pool, type PoolClient, type QueryResultRow } from 'pg';

import { env } from '../config/env';
import { logger } from '../lib/logger';

let pool: Pool | null = null;

export function getPool(): Pool {
  if (pool) return pool;
  if (!env.databaseUrl) {
    throw new Error('DATABASE_URL is not set');
  }
  const conn = env.databaseUrl;
  const useSsl =
    conn.includes('railway') || conn.includes('amazonaws.com') || conn.includes('sslmode=require');
  pool = new Pool({
    connectionString: conn,
    max: 20,
    connectionTimeoutMillis: 8_000,
    idleTimeoutMillis: 30_000,
    ssl: useSsl ? { rejectUnauthorized: false } : undefined,
  });
  pool.on('error', (err) => logger.error({ err }, 'pg_pool_error'));
  return pool;
}

export async function query<T extends QueryResultRow = QueryResultRow>(
  text: string,
  params: unknown[] = [],
): Promise<T[]> {
  const result = await getPool().query<T>(text, params);
  return result.rows;
}

export async function queryOne<T extends QueryResultRow = QueryResultRow>(
  text: string,
  params: unknown[] = [],
): Promise<T | null> {
  const rows = await query<T>(text, params);
  return rows[0] ?? null;
}

export async function transaction<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export async function closePool(): Promise<void> {
  if (pool) {
    await pool.end();
    pool = null;
  }
}
