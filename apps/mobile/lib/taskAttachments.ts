import * as DocumentPicker from 'expo-document-picker';
import { supabase } from './supabase';

export type PickedAttachment = { uri: string; name: string; mimeType: string; size: number };
export async function pickTaskAttachment(): Promise<PickedAttachment | null> {
  const result = await DocumentPicker.getDocumentAsync({ copyToCacheDirectory: true, multiple: false, type: '*/*' });
  if (result.canceled || !result.assets?.[0]) return null;
  const file = result.assets[0];
  if (!file.size || file.size > 20 * 1024 * 1024) throw new Error('attachment_too_large');
  return { uri: file.uri, name: file.name, mimeType: file.mimeType || 'application/octet-stream', size: file.size };
}
export async function uploadTaskAttachment(taskId: string, file: PickedAttachment) {
  if (!supabase) throw new Error('supabase_not_configured');
  const response = await fetch(file.uri);
  const body = await response.arrayBuffer();
  const path = `${taskId}/${Date.now()}-${file.name.replace(/[^a-zA-Z0-9._-]/g, '_')}`;
  const { error } = await supabase.storage.from('task-reports').upload(path, body, { contentType: file.mimeType, upsert: false });
  if (error) throw error;
  return { path, name: file.name, mimeType: file.mimeType, size: file.size };
}
