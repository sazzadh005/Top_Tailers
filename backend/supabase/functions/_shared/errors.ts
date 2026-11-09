import { HttpError } from './types.ts';

interface DbErrorLike { message?: string; hint?: string | null; code?: string | null }

/** Turns a database error into a safe HttpError. Our SQL functions raise user-facing messages. */
export function mapDbError(e: DbErrorLike): HttpError {
  const hint = e.hint ?? '';
  const message = e.message ?? 'Something went wrong.';
  const table: Record<string, number> = {
    UNAUTHENTICATED: 401, FORBIDDEN: 403, ORDER_NOT_FOUND: 404, PAYMENT_UNKNOWN: 404,
    RATE_LIMITED: 429,
  };
  // PostgREST reports an invalid/expired JWT as PGRST301/PGRST302.
  if (e.code === 'PGRST301' || e.code === 'PGRST302' || /JWT/i.test(message)) return new HttpError(401, 'UNAUTHENTICATED', 'Please sign in again.');
  if (hint in table) return new HttpError(table[hint], hint, message);
  if (e.code === 'P0001') return new HttpError(400, hint || 'REQUEST_INVALID', message);
  if (e.code === '28000' || e.code === '42501') return new HttpError(e.code === '28000' ? 401 : 403, hint || 'FORBIDDEN', message);
  // Anything else is unexpected: do not leak internals.
  return new HttpError(500, 'INTERNAL', 'Something went wrong. Please try again.');
}
