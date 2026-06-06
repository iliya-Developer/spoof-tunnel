/**
 * Manage the web path prefix (e.g. "/abc123def") across page refreshes and restarts.
 *
 * Strategy:
 * 1. If the current URL contains a non-known first segment, use it (runtime detection).
 * 2. Otherwise, fall back to localStorage where we persist the last known web-path.
 * 3. When a valid web-path is detected, save it to localStorage for future recovery.
 */

const STORAGE_KEY = 'spoof_web_path';

const knownRoots = ['dashboard', 'login', '_next', 'api'];

function detectFromUrl(): string {
  if (typeof window === 'undefined') return '';
  const parts = window.location.pathname.split('/').filter(Boolean);
  if (parts.length > 0 && !knownRoots.includes(parts[0])) {
    return '/' + parts[0];
  }
  return '';
}

function getStored(): string {
  if (typeof window === 'undefined') return '';
  return localStorage.getItem(STORAGE_KEY) || '';
}

function storePath(path: string): void {
  if (typeof window === 'undefined') return;
  if (path && path !== '/') {
    localStorage.setItem(STORAGE_KEY, path);
  }
}

/**
 * Get the current base path. Tries URL detection first, then falls back to localStorage.
 */
export function getBasePath(): string {
  const fromUrl = detectFromUrl();
  if (fromUrl) {
    storePath(fromUrl);
    return fromUrl;
  }
  const stored = getStored();
  if (stored) {
    return stored;
  }
  return '';
}
