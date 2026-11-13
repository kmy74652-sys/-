import { createClient } from '@supabase/supabase-js';

const rawUrl = (import.meta.env.VITE_SUPABASE_URL as string | undefined) || 'https://fjmryqhdwxsocdzswnkq.supabase.co';
const url = rawUrl?.replace(/\/rest\/v1\/?$/, '');
const anonKey = (import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined) || 'sb_publishable_vRWbeJO5I_KJwJjqVDSZLA_pEHABsPk';

export const supabase = url && anonKey
  ? createClient(url, anonKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
    })
  : null;
