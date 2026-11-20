import { supabase } from './supabase';

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

  const { data, error: readError } = await supabase
    .from('organizations')
    .select('settings')
    .eq('id', organizationId)
    .single();

  if (readError) {
    if (isMissingSettingsColumn(readError)) throw new Error('organization_branding_migration_required');
    throw readError;
  }

  const settings = (data?.settings ?? {}) as Record<string, unknown>;
  const { error } = await supabase
    .from('organizations')
    .update({
      name,
      settings: { ...settings, branding: { tagline, logo_url: logoUrl } },
    })
    .eq('id', organizationId);

  if (error) throw error;
}

export async function uploadOrganizationLogo(organizationId: string, asset: OrganizationLogoAsset) {
  if (!supabase) throw new Error('supabase_not_configured');
  if (!asset.uri || !/^image\/(jpeg|png|webp)$/i.test(asset.mimeType ?? '')) throw new Error('organization_logo_type_invalid');
  const response = await fetch(asset.uri);
  if (!response.ok) throw new Error('organization_logo_read_failed');
  const blob = await response.blob();
  if (blob.size > 5 * 1024 * 1024) throw new Error('organization_logo_too_large');
  const path = `${organizationId}/logo`;
  const { error } = await supabase.storage.from('organization-branding').upload(path, blob, {
    contentType: asset.mimeType ?? 'image/png',
    upsert: true,
    cacheControl: '3600',
  });
  if (error) throw error;
  const { data } = supabase.storage.from('organization-branding').getPublicUrl(path);
  return `${data.publicUrl}?v=${Date.now()}`;
}
