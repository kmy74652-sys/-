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

async function readQueue(): Promise<SyncOperation[]> {
  const raw = await AsyncStorage.getItem(STORAGE_KEY);
  if (!raw) return [];
  try { return JSON.parse(raw) as SyncOperation[]; } catch { return []; }
}

async function writeQueue(queue: SyncOperation[]) { await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(queue)); }

export async function enqueue(operation: Omit<SyncOperation, 'id' | 'createdAt' | 'attempts'>): Promise<SyncOperation> {
  const queue = await readQueue();
  const existing = queue.find((item) => item.idempotencyKey === operation.idempotencyKey);
  if (existing) return existing;
  const item: SyncOperation = { ...operation, id: `${Date.now()}-${Math.random().toString(36).slice(2)}`, createdAt: new Date().toISOString(), attempts: 0 };
  await writeQueue([...queue, item]);
  return item;
}

export async function pendingCount() { return (await readQueue()).length; }

export async function flushQueue(accessToken: string, baseUrl: string): Promise<{ synced: number; pending: number }> {
  const queue = await readQueue(); let synced = 0; const remaining: SyncOperation[] = [];
  for (const item of queue) {
    try {
      const response = await fetch(`${baseUrl}${item.path}`, { method: item.method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}`, 'Idempotency-Key': item.idempotencyKey }, body: item.body === undefined ? undefined : JSON.stringify(item.body) });
      if (response.ok || response.status === 409) synced += 1;
      else remaining.push({ ...item, attempts: item.attempts + 1 });
    } catch { remaining.push({ ...item, attempts: item.attempts + 1 }); }
  }
  await writeQueue(remaining);
  return { synced, pending: remaining.length };
}
