/**
 * Manage the web path prefix (e.g. "/abc123def") across page refreshes and restarts.
 *
 * The web-path is persisted aggressively to localStorage so that even if the
 * URL changes (e.g. after a redirect), the correct prefix can be recovered.
 */

const STORAGE_KEY = 'spoof_web_path';

const knownRoots = ['dashboard', 'login', '_next', 'api'];

/**
 * Try to detect the web-path from the current browser URL.
 * URL like /abc123def/login → first segment "abc123def" is NOT a known root → path = "/abc123def"
 * URL like /login             → first segment "login"   IS  a known root   → path = ""
 */
function detectFromUrl(): string {
  if (typeof window === 'undefined') return '';
  const parts = window.location.pathname.split('/').filter(Boolean);
  if (parts.length > 0 && !knownRoots.includes(parts[0])) {
    return '/' + parts[0];
  }
  return '';
}

/** Read the previously saved web-path from localStorage */
function getStored(): string {
  if (typeof window === 'undefined') return '';
  return localStorage.getItem(STORAGE_KEY) || '';
}

/** Persist a web-path to localStorage */
function storePath(path: string): void {
  if (typeof window === 'undefined') return;
  if (path && path !== '/') {
    localStorage.setItem(STORAGE_KEY, path);
  }
}

/**
 * Get the current base path.
 *
 * 1. Try to detect from URL  → if found, save to localStorage and return
 * 2. Fall back to localStorage → if found, return
 * 3. Return empty string
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

/**
 * Build the full login URL with the web-path preserved.
 * This is the ONLY way to build a login redirect URL — it guarantees
 * the web-path is included even if getBasePath() returns empty.
 */
export function getLoginUrl(): string {
  const base = getBasePath();
  return base + '/login';
}
