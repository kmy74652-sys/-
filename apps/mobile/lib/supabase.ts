import { createClient } from '@supabase/supabase-js';
import 'react-native-url-polyfill/auto';

const rawUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
const url = rawUrl?.replace(/\/rest\/v1\/?$/, '');
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;
export const supabase = url && anonKey ? createClient(url, anonKey, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false } }) : null;
