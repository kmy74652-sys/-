type SessionCacheEntry<T> = { value: T; storedAt: number };

const cache = new Map<string, SessionCacheEntry<unknown>>();
const DEFAULT_MAX_AGE_MS = 120_000;

export function readSessionCache<T>(namespace: string, key: string, maxAgeMs = DEFAULT_MAX_AGE_MS): T | null {
  const entry = cache.get(`${namespace}:${key}`) as SessionCacheEntry<T> | undefined;
  if (!entry) return null;
  if (Date.now() - entry.storedAt > maxAgeMs) {
    cache.delete(`${namespace}:${key}`);
    return null;
  }
  return entry.value;
}

export function writeSessionCache<T>(namespace: string, key: string, value: T) {
  cache.set(`${namespace}:${key}`, { value, storedAt: Date.now() });
}

export function clearSessionCache(namespace?: string) {
  if (!namespace) {
    cache.clear();
    return;
  }
  for (const key of cache.keys()) if (key.startsWith(`${namespace}:`)) cache.delete(key);
}
