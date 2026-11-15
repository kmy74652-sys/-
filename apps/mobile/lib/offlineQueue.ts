import AsyncStorage from '@react-native-async-storage/async-storage';

export type QueueKind = 'status' | 'report';
export type QueueItem = { id: string; kind: QueueKind; payload: Record<string, unknown>; attempts: number; createdAt: string; nextAttemptAt: string };
const KEY = '@alshaeri/mobile-offline-queue/v1';
const MAX_ATTEMPTS = 8;

async function read(): Promise<QueueItem[]> {
  const raw = await AsyncStorage.getItem(KEY);
  if (!raw) return [];
  try { return JSON.parse(raw) as QueueItem[]; } catch { return []; }
}
async function write(items: QueueItem[]) { await AsyncStorage.setItem(KEY, JSON.stringify(items)); }
export async function queueOperation(kind: QueueKind, payload: Record<string, unknown>, id = `${kind}:${String(payload.taskId)}:${String(payload.idempotencyKey)}`) {
  const items = await read();
  if (!items.some((item) => item.id === id)) items.push({ id, kind, payload, attempts: 0, createdAt: new Date().toISOString(), nextAttemptAt: new Date(0).toISOString() });
  await write(items);
}
export async function pendingOperations() { return read(); }
export async function removeOperation(id: string) { await write((await read()).filter((item) => item.id !== id)); }
export async function markRetry(item: QueueItem) {
  const items = await read();
  const delay = Math.min(30 * 60_000, 2 ** Math.min(item.attempts, 8) * 1000);
  await write(items.map((candidate) => candidate.id === item.id ? { ...candidate, attempts: candidate.attempts + 1, nextAttemptAt: new Date(Date.now() + delay).toISOString() } : candidate));
}
export async function flushQueue(execute: (item: QueueItem) => Promise<void>) {
  const now = Date.now();
  for (const item of await read()) {
    if (item.attempts >= MAX_ATTEMPTS || new Date(item.nextAttemptAt).getTime() > now) continue;
    try { await execute(item); await removeOperation(item.id); } catch { await markRetry(item); }
  }
}
export const offlineQueueStorageKey = KEY;
