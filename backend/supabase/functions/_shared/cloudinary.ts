import { CloudinaryConfig, FetchFn, HttpError } from './types.ts';

// Signed uploads per Cloudinary's documented scheme: sort the parameters by name,
// join as key=value with &, append the API secret, SHA-1 hex. `file`, `cloud_name`,
// `resource_type` and `api_key` are never signed.
// Docs: https://cloudinary.com/documentation/authentication_signatures

const UNSIGNED = new Set(['file', 'cloud_name', 'resource_type', 'api_key']);

async function sha1Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function signParams(params: Record<string, string | number | boolean>, apiSecret: string): Promise<string> {
  const toSign = Object.keys(params)
    .filter((k) => !UNSIGNED.has(k) && params[k] !== '' && params[k] !== undefined && params[k] !== null)
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join('&');
  return sha1Hex(toSign + apiSecret);
}

export interface UploadTicket {
  cloudName: string;
  apiKey: string;
  timestamp: number;
  signature: string;
  publicId: string;
  allowedFormats: string;
  overwrite: boolean;
  uploadUrl: string;
}

const ALLOWED_FORMATS = 'jpg,jpeg,png,webp';

/** The client may only upload to the public id the SERVER chose. */
export async function createUploadTicket(
  cfg: CloudinaryConfig,
  publicId: string,
  opts: { overwrite: boolean; now?: () => number },
): Promise<UploadTicket> {
  const timestamp = Math.floor((opts.now ?? Date.now)() / 1000);
  const toSign = {
    allowed_formats: ALLOWED_FORMATS,
    overwrite: opts.overwrite,
    public_id: publicId,
    timestamp,
    ...(opts.overwrite ? { invalidate: true } : {}),
  };
  const signature = await signParams(toSign, cfg.apiSecret);
  return {
    cloudName: cfg.cloudName,
    apiKey: cfg.apiKey,
    timestamp,
    signature,
    publicId,
    allowedFormats: ALLOWED_FORMATS,
    overwrite: opts.overwrite,
    uploadUrl: `https://api.cloudinary.com/v1_1/${cfg.cloudName}/image/upload`,
  };
}

/** Destroys one asset (used by the cleanup job, never by clients). */
export async function destroyAsset(fetchFn: FetchFn, cfg: CloudinaryConfig, publicId: string, now: () => number = Date.now): Promise<void> {
  const timestamp = Math.floor(now() / 1000);
  const signature = await signParams({ invalidate: true, public_id: publicId, timestamp }, cfg.apiSecret);
  const form = new URLSearchParams({
    public_id: publicId, timestamp: String(timestamp), invalidate: 'true', api_key: cfg.apiKey, signature,
  });
  let res: Response;
  try {
    res = await fetchFn(`https://api.cloudinary.com/v1_1/${cfg.cloudName}/image/destroy`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form.toString(),
      signal: AbortSignal.timeout(15000),
    });
  } catch {
    throw new HttpError(502, 'CLOUDINARY_UNREACHABLE', 'Cloudinary is not reachable.');
  }
  const body = (await res.json().catch(() => ({}))) as { result?: string };
  // "not found" means the asset is already gone, which is what we want.
  if (!res.ok || (body.result !== 'ok' && body.result !== 'not found')) {
    throw new HttpError(502, 'CLOUDINARY_FAILED', `Cloudinary refused to delete the asset (${body.result ?? res.status}).`);
  }
}
