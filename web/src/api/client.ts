// JSON requests to the GG Store API. Authentication is the API's httpOnly `token` cookie (set by
// POST /api/auth/login), so no token is ever held in JavaScript.

const BASE = (import.meta.env.VITE_API_URL as string | undefined) ?? '';

/** An error carrying the API's own (Indonesian) message. */
export class ApiError extends Error {
  readonly status: number;
  readonly body: unknown;

  constructor(message: string, status: number, body: unknown) {
    super(message);
    this.status = status;
    this.body = body;
  }
}

export type Query = Record<string, string | number | boolean | null | undefined>;

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE';
  query?: Query;
  body?: unknown;
  signal?: AbortSignal;
}

/** Fired when the session is gone (401), so the app can return to the login page. */
export const SESSION_EXPIRED = 'gg:session-expired';

export async function api<T>(path: string, { method = 'GET', query, body, signal }: RequestOptions = {}): Promise<T> {
  const url = new URL(`${BASE}/api${path}`, window.location.origin);
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value !== undefined && value !== null && value !== '') url.searchParams.set(key, String(value));
  }

  const isForm = body instanceof FormData;
  let res: Response;
  try {
    res = await fetch(url, {
      method,
      credentials: 'include',
      signal,
      headers: body !== undefined && !isForm ? { 'Content-Type': 'application/json' } : undefined,
      body: body === undefined ? undefined : isForm ? body : JSON.stringify(body),
    });
  } catch (error) {
    if ((error as Error).name === 'AbortError') throw error;
    throw new ApiError('Tidak dapat terhubung ke server', 0, null);
  }

  const data: unknown = await res.json().catch(() => null);
  if (!res.ok) {
    if (res.status === 401 && path !== '/auth/login' && path !== '/auth/me') {
      window.dispatchEvent(new Event(SESSION_EXPIRED));
    }
    const message =
      data && typeof data === 'object' && 'error' in data && typeof data.error === 'string'
        ? data.error
        : `Permintaan gagal (${res.status})`;
    throw new ApiError(message, res.status, data);
  }
  return data as T;
}

export const errorMessage = (error: unknown): string =>
  error instanceof Error ? error.message : 'Terjadi kesalahan';

/** URL for an uploaded file (product and category images). */
export const uploadUrl = (folder: 'products' | 'categories', file?: string | null): string | null =>
  file ? `${BASE}/uploads/${folder}/${file}` : null;
