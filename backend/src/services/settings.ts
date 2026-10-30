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

function compareVersions(a: string, b: string): number {
  const x = a.split('.').map((p) => Number.parseInt(p, 10) || 0);
  const y = b.split('.').map((p) => Number.parseInt(p, 10) || 0);
  for (let i = 0; i < 3; i++) {
    const d = (x[i] ?? 0) - (y[i] ?? 0);
    if (d !== 0) return Math.sign(d);
  }
  return 0;
}

export async function getAppConfig() {
  const [maintenance, update, support, refresh] = await Promise.all([
    getSetting('maintenance'),
    getSetting('app_update'),
    getSetting('support'),
    getSetting('refresh'),
  ]);
  // Apps block below minVersion, so "must update" has to cover everything
  // older than the latest release, including apps already installed.
  const minVersion =
    update.force && compareVersions(update.latestVersion, update.minVersion) > 0
      ? update.latestVersion
      : update.minVersion;
  return {
    maintenance,
    update: { ...update, minVersion },
    supportWhatsApp: support.whatsapp,
    refreshToken: refresh.token,
  };
}
