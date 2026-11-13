import AsyncStorage from '@react-native-async-storage/async-storage';

export type SyncOperation = {
  id: string;
  path: string;
  method: 'POST' | 'PATCH' | 'DELETE';
  body?: unknown;
  idempotencyKey: string;
  createdAt: string;
  attempts: number;
};

const STORAGE_KEY = '@alshaeri/sync-queue/v1';

let storageLock: Promise<void> = Promise.resolve();
let activeFlush: Promise<{ synced: number; pending: number }> | null = null;

async function withStorageLock<T>(operation: () => Promise<T>): Promise<T> {
  const result = storageLock.then(operation, operation);
  storageLock = result.then(() => undefined, () => undefined);
  return result;
}

async function readQueue(): Promise<SyncOperation[]> {
  const raw = await AsyncStorage.getItem(STORAGE_KEY);
  if (!raw) return [];

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error('sync_queue_corrupted');
  }
  if (!Array.isArray(parsed)) throw new Error('sync_queue_corrupted');

  const valid = parsed.every((item): item is SyncOperation =>
    item !== null && typeof item === 'object' &&
    typeof item.id === 'string' && typeof item.path === 'string' &&
    ['POST', 'PATCH', 'DELETE'].includes(item.method) &&
    typeof item.idempotencyKey === 'string' && typeof item.createdAt === 'string' &&
    Number.isInteger(item.attempts) && item.attempts >= 0,
  );
  if (!valid) throw new Error('sync_queue_corrupted');
  return parsed;
}

async function writeQueue(queue: SyncOperation[]) {
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(queue));
}

export async function enqueue(operation: Omit<SyncOperation, 'id' | 'createdAt' | 'attempts'>): Promise<SyncOperation> {
  return withStorageLock(async () => {
    const queue = await readQueue();
    const existing = queue.find((item) => item.idempotencyKey === operation.idempotencyKey);
    if (existing) return existing;
    const item: SyncOperation = {
      ...operation,
      id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
      createdAt: new Date().toISOString(),
      attempts: 0,
    };
    await writeQueue([...queue, item]);
    return item;
  });
}

export async function pendingCount() {
  return withStorageLock(async () => (await readQueue()).length);
}

async function flushQueueOnce(accessToken: string, baseUrl: string): Promise<{ synced: number; pending: number }> {
  const queue = await withStorageLock(readQueue);
  const succeededIds = new Set<string>();
  const retryOperations = new Map<string, SyncOperation>();
  let synced = 0;

  for (const item of queue) {
    try {
      const response = await fetch(`${baseUrl}${item.path}`, {
        method: item.method,
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${accessToken}`,
          'Idempotency-Key': item.idempotencyKey,
        },
        body: item.body === undefined ? undefined : JSON.stringify(item.body),
      });
      if (response.ok) {
        succeededIds.add(item.id);
        synced += 1;
      } else {
        // Keep conflicts (including 409) until the server contract identifies a safe replay.
        retryOperations.set(item.id, { ...item, attempts: item.attempts + 1 });
      }
    } catch {
      retryOperations.set(item.id, { ...item, attempts: item.attempts + 1 });
    }
  }

  return withStorageLock(async () => {
    // Re-read before writing so items enqueued while network requests were running survive.
    const current = await readQueue();
    const merged = current.flatMap((item) => {
      if (succeededIds.has(item.id)) return [];
      return [retryOperations.get(item.id) ?? item];
    });
    await writeQueue(merged);
    return { synced, pending: merged.length };
  });
}

export function flushQueue(accessToken: string, baseUrl: string): Promise<{ synced: number; pending: number }> {
  if (activeFlush) return activeFlush;
  activeFlush = flushQueueOnce(accessToken, baseUrl).finally(() => {
    activeFlush = null;
  });
  return activeFlush;
}
