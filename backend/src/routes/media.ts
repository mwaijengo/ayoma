import express, { Router, type Request } from 'express';

import { query, queryOne } from '../db/pool';
import { HttpError, intParam, route } from '../lib/http';
import { requireAdmin } from '../middleware/auth';

export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

/** Absolute URL of this server as seen by the caller (Railway sits behind a proxy). */
function publicBase(req: Request): string {
  return `${req.protocol}://${req.get('host')}`;
}

/** Images stored in Postgres: admins upload, everyone can read. */
export const mediaRouter = Router();

mediaRouter.post(
  '/',
  requireAdmin,
  express.raw({ type: IMAGE_TYPES, limit: MAX_IMAGE_BYTES }),
  route(async (req, res) => {
    const mime = (req.headers['content-type'] ?? '').split(';')[0]!.trim().toLowerCase();
    if (!IMAGE_TYPES.includes(mime)) {
      throw new HttpError(415, 'Only JPG, PNG, WebP or GIF images can be uploaded', 'BAD_IMAGE_TYPE');
    }
    const data = req.body;
    if (!Buffer.isBuffer(data) || data.length === 0) {
      throw new HttpError(400, 'The image is empty', 'EMPTY_IMAGE');
    }
    const row = await queryOne<{ id: number }>(
      'INSERT INTO media (mime, data, size_bytes) VALUES ($1, $2, $3) RETURNING id',
      [mime, data, data.length],
    );
    const id = row!.id;
    res.status(201).json({
      media: { id, mime, sizeBytes: data.length, url: `${publicBase(req)}/api/v1/media/${id}` },
    });
  }),
);

mediaRouter.get(
  '/:id',
  route(async (req, res) => {
    const id = intParam(req, 'id');
    const etag = `"media-${id}"`;
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    res.setHeader('ETag', etag);
    // Lets the apps (and the admin web build) show images from this API.
    res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
    if (req.headers['if-none-match'] === etag) {
      res.status(304).end();
      return;
    }
    const rows = await query<{ mime: string; data: Buffer }>('SELECT mime, data FROM media WHERE id = $1', [id]);
    const image = rows[0];
    if (!image) throw new HttpError(404, 'Image not found', 'MEDIA_NOT_FOUND');
    res.type(image.mime).send(image.data);
  }),
);
