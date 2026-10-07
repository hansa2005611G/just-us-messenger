import { createClient } from '@supabase/supabase-js';

const env = import.meta.env;
export const missingSupabaseSettings = [
  'VITE_SUPABASE_URL',
  'VITE_SUPABASE_PUBLISHABLE_KEY',
].filter((key) => !env[key]);

export const supabase = missingSupabaseSettings.length
  ? null
  : createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_PUBLISHABLE_KEY, {
      auth: {
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: true,
      },
    });
