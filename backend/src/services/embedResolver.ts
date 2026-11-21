import { logger } from '../lib/logger';

/**
 * Resolves `…/embed.php?app=<n>&key=<k>` pages (e.g. sokamax.live) into a real
 * DASH/HLS URL plus Widevine licence details. The page itself is only a JS
 * shell; the stream comes from `player.php?…&api=1`.
 */

export type ResolvedEmbed = {
  streamUrl: string;
  streamType: 'dash' | 'hls';
  licenseUrl?: string;
  drmType?: 'widevine';
  headers: Record<string, string>;
  licenseHeaders: Record<string, string>;
};

const CACHE_MS = 60_000;
const cache = new Map<string, { at: number; value: ResolvedEmbed }>();

const PACKAGE_NAME = (process.env.EMBED_PACKAGE_NAME || 'com.ayoma').trim() || 'com.ayoma';

const BROWSER_UA =
  'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/90.0.4430.91 Mobile Safari/537.36';

export function isEmbedApiPlayer(url: string): boolean {
  try {
    const parsed = new URL(url.trim());
    if (!parsed.pathname.toLowerCase().endsWith('/embed.php')) return false;
    return Boolean(parsed.searchParams.get('app') && parsed.searchParams.get('key'));
  } catch {
    return false;
  }
}

type EmbedApiJson = {
  success?: boolean;
  mpdPath?: string;
  licenseUrl?: string;
  authXmlToken?: string;
  error?: unknown;
  message?: unknown;
};

export async function resolveEmbedApi(playerUrl: string): Promise<ResolvedEmbed | null> {
  const key = playerUrl.trim();
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.value;

  let parsed: URL;
  try {
    parsed = new URL(key);
  } catch {
    return null;
  }

  const app = parsed.searchParams.get('app');
  const streamKey = parsed.searchParams.get('key');
  if (!app || !streamKey) return null;

  const origin = parsed.origin;
  const apiUrl = `${origin}/player.php?app=${encodeURIComponent(app)}&key=${encodeURIComponent(streamKey)}&api=1`;

  let status = 0;
  let data: EmbedApiJson | null = null;
  try {
    const resp = await fetch(apiUrl, {
      headers: {
        'User-Agent': BROWSER_UA,
        Accept: 'application/json',
        'X-Requested-With': PACKAGE_NAME,
        Referer: `${origin}/`,
      },
      redirect: 'follow',
      signal: AbortSignal.timeout(15_000),
    });
    status = resp.status;
    data = status === 200 ? ((await resp.json()) as EmbedApiJson) : null;
  } catch (err) {
    logger.error({ err, apiUrl }, 'embed_api_failed');
    return null;
  }

  const streamUrl = typeof data?.mpdPath === 'string' ? data.mpdPath.trim() : '';
  if (!data?.success || !streamUrl) {
    logger.error(
      {
        status,
        error: String(data?.error ?? data?.message ?? '').slice(0, 120),
      },
      'embed_api_no_stream',
    );
    return null;
  }

  const headers: Record<string, string> = {
    'User-Agent': 'ExoPlayer',
    Referer: `${origin}/`,
  };
  const licenseHeaders: Record<string, string> = {};
  const token = typeof data.authXmlToken === 'string' ? data.authXmlToken.trim() : '';
  // Nagra Widevine rejects the licence call without this header.
  if (token) licenseHeaders['nv-authorizations'] = token;

  const licenseUrl = typeof data.licenseUrl === 'string' ? data.licenseUrl.trim() : '';
  const result: ResolvedEmbed = {
    streamUrl,
    streamType: streamUrl.toLowerCase().includes('.mpd') ? 'dash' : 'hls',
    headers,
    licenseHeaders,
    ...(licenseUrl ? { licenseUrl, drmType: 'widevine' as const } : {}),
  };

  cache.set(key, { at: Date.now(), value: result });
  logger.info({ streamUrl }, 'embed_api_resolved');
  return result;
}
