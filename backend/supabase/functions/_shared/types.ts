// Shared types. These modules are runtime-neutral (Deno and Node) so they can
// be unit tested; only the index.ts entry points touch Deno or supabase-js.

export interface AamarPayConfig {
  /** https://sandbox.aamarpay.com (sandbox) or https://secure.aamarpay.com (live) */
  baseUrl: string;
  storeId: string;
  /** SECRET. Comes from Edge Function secrets only. Never logged, never returned. */
  signatureKey: string;
  /** Public base of this project's functions, e.g. https://<ref>.supabase.co/functions/v1 */
  functionsBase: string;
  /** Optional page or deep link the browser is sent to after the callback. */
  returnUrl?: string;
}

export interface CloudinaryConfig {
  cloudName: string;
  apiKey: string;
  /** SECRET. Comes from Edge Function secrets only. */
  apiSecret: string;
}

export interface AttemptStart {
  tranId: string;
  amountMinor: number;
  amountDecimal: string;
  currency: string;
  orderId: string;
  orderReference: string;
  customerName: string;
  customerEmail: string;
  customerPhone: string;
  customerAddress: string;
  description: string;
  paymentUrl: string | null;
  status: string;
}

export interface AttemptInfo {
  tranId: string;
  orderId: string;
  amountMinor: number;
  currency: string;
  status: string;
}

/** What the server learned from the provider's verification API. */
export interface VerifiedTransaction {
  statusCode: string;
  payStatus?: string;
  merTxnId?: string;
  pgTxnId?: string;
  amount?: string;
  currency?: string;
  storeId?: string;
  paymentType?: string;
}

export interface PaymentOutcome {
  outcome: string;
  orderId?: string;
  reason?: string;
}

export interface PaymentsDb {
  /** Runs with the CUSTOMER's JWT, so ownership is enforced by the database. */
  startAttempt(accessToken: string, orderId: string, idempotencyKey?: string): Promise<AttemptStart>;
  attachUrl(tranId: string, url: string): Promise<void>;
  attemptInfo(tranId: string): Promise<AttemptInfo | null>;
  recordResult(tranId: string, verified: VerifiedTransaction, expectedStore: string): Promise<PaymentOutcome>;
  recordCancel(tranId: string): Promise<PaymentOutcome>;
}

export interface WhoAmI {
  id: string;
  role: 'customer' | 'admin';
}

export interface MediaDb {
  whoAmI(accessToken: string): Promise<WhoAmI>;
  recordTicket(publicId: string, userId: string): Promise<void>;
  queueOrphans(): Promise<number>;
  claimCleanup(limit: number): Promise<string[]>;
  completeCleanup(ids: string[]): Promise<void>;
  failCleanup(id: string, error: string): Promise<void>;
}

/** A failure with a safe, user-facing message. */
export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

export type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;
