import { AamarPayConfig, CloudinaryConfig } from './types.ts';

type Getter = (name: string) => string | undefined;

function need(get: Getter, name: string): string {
  const v = get(name)?.trim();
  if (!v) throw new Error(`Missing required secret/environment variable ${name}. See docs/BACKEND_SETUP.md.`);
  return v;
}

/** Secrets are read from Edge Function secrets at start-up; values are never logged. */
export function loadAamarPayConfig(get: Getter): AamarPayConfig {
  const base = (get('AAMARPAY_BASE_URL')?.trim() || 'https://sandbox.aamarpay.com').replace(/\/$/, '');
  if (!/^https:\/\/(sandbox|secure)\.aamarpay\.com$/.test(base)) {
    throw new Error('AAMARPAY_BASE_URL must be https://sandbox.aamarpay.com or https://secure.aamarpay.com');
  }
  const functionsBase = get('FUNCTIONS_BASE_URL')?.trim() || `${need(get, 'SUPABASE_URL').replace(/\/$/, '')}/functions/v1`;
  const returnUrl = get('PAYMENT_RETURN_URL')?.trim() || undefined;
  if (returnUrl && !/^(https:\/\/|[a-z][a-z0-9+.-]*:\/\/)/i.test(returnUrl)) {
    throw new Error('PAYMENT_RETURN_URL must be an https URL or an app deep link.');
  }
  return { baseUrl: base, storeId: need(get, 'AAMARPAY_STORE_ID'), signatureKey: need(get, 'AAMARPAY_SIGNATURE_KEY'), functionsBase, returnUrl };
}

export function loadCloudinaryConfig(get: Getter): CloudinaryConfig {
  return {
    cloudName: need(get, 'CLOUDINARY_CLOUD_NAME'),
    apiKey: need(get, 'CLOUDINARY_API_KEY'),
    apiSecret: need(get, 'CLOUDINARY_API_SECRET'),
  };
}
