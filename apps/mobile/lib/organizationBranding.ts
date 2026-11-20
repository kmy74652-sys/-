import { supabase } from './supabase';
import * as FileSystem from 'expo-file-system';

const DEFAULT_ORGANIZATION_NAME = 'مؤسسة الشاعري للتجارة العامة';
const DEFAULT_TAGLINE = 'معًا... نحو إدارة أفضل';

export type OrganizationBranding = {
  name: string;
  tagline: string;
  logoUrl: string | null;
  settingsAvailable: boolean;
};

export type OrganizationLogoAsset = {
  uri: string;
  mimeType?: string | null;
};

function decodeBase64ToArrayBuffer(value: string): ArrayBuffer {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const clean = value.replace(/[^A-Za-z0-9+/=]/g, '');
  const outputLength = Math.floor(clean.length * 3 / 4) - (clean.endsWith('==') ? 2 : clean.endsWith('=') ? 1 : 0);
  const output = new Uint8Array(outputLength);
  let buffer = 0;
  let bits = 0;
  let offset = 0;
  for (const character of clean) {
    if (character === '=') break;
    buffer = (buffer << 6) | alphabet.indexOf(character);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      output[offset++] = (buffer >> bits) & 0xff;
    }
  }
  return output.buffer;
}

function isMissingSettingsColumn(error: unknown) {
  const value = error as { code?: string; message?: string } | null;
  const message = value?.message ?? '';
  return value?.code === '42703'
    || value?.code === 'PGRST204'
    || /column .*settings.* does not exist|could not find the 'settings' column/i.test(message);
}

export async function loadOrganizationBranding(organizationId: string): Promise<OrganizationBranding> {
  if (!supabase) throw new Error('supabase_not_configured');

  const { data, error } = await supabase
    .from('organizations')
    .select('name,settings')
    .eq('id', organizationId)
    .maybeSingle();

  if (error) {
    if (!isMissingSettingsColumn(error)) throw error;
    const fallback = await supabase
      .from('organizations')
      .select('name')
      .eq('id', organizationId)
      .maybeSingle();
    if (fallback.error) throw fallback.error;
    return {
      name: typeof fallback.data?.name === 'string' ? fallback.data.name : DEFAULT_ORGANIZATION_NAME,
      tagline: DEFAULT_TAGLINE,
      logoUrl: null,
      settingsAvailable: false,
    };
  }

  const settings = (data?.settings ?? {}) as Record<string, unknown>;
  const branding = settings.branding && typeof settings.branding === 'object'
    ? settings.branding as Record<string, unknown>
    : {};
  return {
    name: typeof data?.name === 'string' ? data.name : DEFAULT_ORGANIZATION_NAME,
    tagline: typeof branding.tagline === 'string' ? branding.tagline : DEFAULT_TAGLINE,
    logoUrl: typeof branding.logo_url === 'string' ? branding.logo_url : null,
    settingsAvailable: true,
  };
}

export async function saveOrganizationBranding(
  organizationId: string,
  name: string,
  tagline: string,
  logoUrl: string | null,
) {
  if (!supabase) throw new Error('supabase_not_configured');
  const { error } = await supabase.rpc('save_organization_branding', {
    p_organization_id: organizationId,
    p_name: name,
    p_tagline: tagline,
    p_logo_url: logoUrl,
  });
  if (error) throw error;
}

export async function uploadOrganizationLogo(organizationId: string, asset: OrganizationLogoAsset) {
  if (!supabase) throw new Error('supabase_not_configured');
  const extension = asset.uri.toLowerCase().split('?')[0].split('.').pop();
  const mimeType = /^image\/(jpeg|png|webp)$/i.test(asset.mimeType ?? '')
    ? asset.mimeType!.toLowerCase()
    : extension === 'jpg' || extension === 'jpeg' ? 'image/jpeg' : extension === 'webp' ? 'image/webp' : extension === 'png' ? 'image/png' : '';
  if (!asset.uri || !mimeType) throw new Error('organization_logo_type_invalid');
  let base64: string;
  try {
    base64 = await FileSystem.readAsStringAsync(asset.uri, { encoding: FileSystem.EncodingType.Base64 });
  } catch {
    throw new Error('organization_logo_read_failed');
  }
  const bytes = decodeBase64ToArrayBuffer(base64);
  if (!bytes.byteLength) throw new Error('organization_logo_read_failed');
  if (bytes.byteLength > 5 * 1024 * 1024) throw new Error('organization_logo_too_large');
  const path = `${organizationId}/logo`;
  const { error } = await supabase.storage.from('organization-branding').upload(path, bytes, {
    contentType: mimeType,
    upsert: true,
    cacheControl: '3600',
  });
  if (error) throw error;
  const { data } = supabase.storage.from('organization-branding').getPublicUrl(path);
  return `${data.publicUrl}?v=${Date.now()}`;
}
