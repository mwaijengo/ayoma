import 'dotenv/config';

function str(name: string, fallback = ''): string {
  return (process.env[name] ?? fallback).trim();
}

const nodeEnv = str('NODE_ENV', 'development');

export const env = {
  nodeEnv,
  isProd: nodeEnv === 'production',
  port: Number(str('PORT', '8080')) || 8080,
  corsOrigin: str('CORS_ORIGIN', '*'),
  databaseUrl: str('DATABASE_URL'),

  jwtSecret: str('JWT_SECRET'),
  adminPassword: str('ADMIN_PASSWORD'),

  sonicPesaApiKey: str('SONICPESA_API_KEY'),
  sonicPesaSecretKey: str('SONICPESA_SECRET_KEY'),
  sonicPesaWebhookSecret: str('SONICPESA_WEBHOOK_SECRET'),

  /** The Firebase service account JSON, base64-encoded (safest to paste). */
  fcmServiceAccountBase64: str('FCM_SERVICE_ACCOUNT_BASE64'),
  fcmServiceAccountJson: str('FCM_SERVICE_ACCOUNT_JSON'),
  fcmServiceAccountPath: str('FCM_SERVICE_ACCOUNT_PATH'),
};

/** Admin sessions always expire after 24 hours. */
export const ADMIN_SESSION_HOURS = 24;

/** Business day boundaries (today's revenue) use Tanzanian time. */
export const BUSINESS_TZ = 'Africa/Dar_es_Salaam';
