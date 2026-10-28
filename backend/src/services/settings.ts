import { DEFAULT_SETTINGS } from '../db/migrate';
import { query, queryOne } from '../db/pool';

export type MaintenanceSettings = { enabled: boolean; message: string };
export type AppUpdateSettings = {
  latestVersion: string;
  minVersion: string;
  force: boolean;
  message: string;
  url: string;
};
export type SupportSettings = { whatsapp: string };
export type RefreshSettings = { token: number };

type SettingsMap = {
  maintenance: MaintenanceSettings;
  app_update: AppUpdateSettings;
  support: SupportSettings;
  refresh: RefreshSettings;
};

export async function getSetting<K extends keyof SettingsMap>(key: K): Promise<SettingsMap[K]> {
  const row = await queryOne<{ value: SettingsMap[K] }>(
    'SELECT value FROM settings WHERE key = $1',
    [key],
  );
  return { ...(DEFAULT_SETTINGS[key] as SettingsMap[K]), ...(row?.value ?? {}) };
}

export async function setSetting<K extends keyof SettingsMap>(
  key: K,
  value: SettingsMap[K],
): Promise<SettingsMap[K]> {
  await query(
    `INSERT INTO settings (key, value, updated_at) VALUES ($1, $2, now())
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
    [key, JSON.stringify(value)],
  );
  return value;
}

/** Changing the token makes every user app restart and reload its data. */
export async function bumpRefreshToken(): Promise<number> {
  const token = Date.now();
  await setSetting('refresh', { token });
  return token;
}

export async function getAppConfig() {
  const [maintenance, update, support, refresh] = await Promise.all([
    getSetting('maintenance'),
    getSetting('app_update'),
    getSetting('support'),
    getSetting('refresh'),
  ]);
  return {
    maintenance,
    update,
    supportWhatsApp: support.whatsapp,
    refreshToken: refresh.token,
  };
}
