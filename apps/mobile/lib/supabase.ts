import { createClient } from '@supabase/supabase-js';
import AsyncStorage from '@react-native-async-storage/async-storage';
import 'react-native-url-polyfill/auto';

const rawUrl = process.env.EXPO_PUBLIC_SUPABASE_URL || 'https://qoeruidmtsasvhxejyga.supabase.co';
const url = rawUrl?.replace(/\/rest\/v1\/?$/, '');
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY || 'sb_publishable_9eVggM535cGiWxO6GBe9TA_o8HL_o6y';
export const supabase = url && anonKey ? createClient(url, anonKey, {
  auth: {
    storage: AsyncStorage,
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false,
  },
}) : null;
