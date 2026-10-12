import { supabase } from './supabase';

export type CreateUserResult =
  | { ok: true; user_id: string; email: string; password: string; role: string; display_name: string }
  | { ok: false; error: string; message?: string };

function generatePassword(len = 12): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789@#$!';
  const arr = crypto.getRandomValues(new Uint8Array(len));
  return Array.from(arr, (b) => chars[b % chars.length]).join('');
}

export async function adminCreateUser(input: {
  email: string;
  display_name?: string;
  phone?: string;
  role: 'vendor' | 'delivery';
  vendor_id?: string;
}): Promise<CreateUserResult> {
  // Try Edge Function first
  try {
    const { data, error } = await supabase.functions.invoke('admin-create-user', { body: input });
    if (!error && data && !data.error) {
      return { ok: true, ...data };
    }
  } catch { /* Edge Function not deployed — fall through */ }

  // Fallback: sign up via client auth + update profile
  const password = generatePassword(14);
  const displayName = input.display_name || input.email.split('@')[0];

  const { data: signUpData, error: signUpErr } = await supabase.auth.signUp({
    email: input.email,
    password,
    options: { data: { display_name: displayName } },
  });

  if (signUpErr) return { ok: false, error: 'create_failed', message: signUpErr.message };
  if (!signUpData.user) return { ok: false, error: 'create_failed', message: 'User creation failed.' };

  const userId = signUpData.user.id;

  // Update profile with role
  await supabase.from('profiles').update({
    role: input.role,
    display_name: displayName,
    phone: input.phone || null,
  }).eq('id', userId);

  // Role-specific setup
  if (input.role === 'vendor' && input.vendor_id) {
    await supabase.from('vendor_members').insert({ vendor_id: input.vendor_id, user_id: userId, role: 'owner' });
  }
  if (input.role === 'delivery') {
    await supabase.from('delivery_partner_profiles').upsert({
      user_id: userId,
      status: 'approved',
      vehicle_type: 'bike',
      vehicle_number: '',
    }, { onConflict: 'user_id' });
  }

  // Re-login as admin (signUp switches the session)
  // The admin needs to refresh to get their session back
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    return {
      ok: true,
      user_id: userId,
      email: input.email,
      password,
      role: input.role,
      display_name: displayName,
    };
  }

  return {
    ok: true,
    user_id: userId,
    email: input.email,
    password,
    role: input.role,
    display_name: displayName,
  };
}
