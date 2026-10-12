import { supabase } from './supabase';

export type CreateUserResult =
  | { ok: true; user_id: string; email: string; password: string; role: string; display_name: string }
  | { ok: false; error: string; message?: string };

export async function adminCreateUser(input: {
  email: string;
  display_name?: string;
  phone?: string;
  role: 'vendor' | 'delivery';
  vendor_id?: string;
}): Promise<CreateUserResult> {
  const { data, error } = await supabase.functions.invoke('admin-create-user', { body: input });
  if (error) return { ok: false, error: 'invoke_failed', message: error.message };
  if (!data || data.error) return { ok: false, error: data?.error ?? 'failed', message: data?.message };
  return { ok: true, ...data };
}
