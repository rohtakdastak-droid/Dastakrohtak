// supabase/functions/admin-create-user/index.ts
//
// Admin-only Edge Function: creates a Supabase auth user with an auto-generated
// password, sets their role, and optionally links them to a vendor.
//
// Requires service_role key (never exposed to browser).
// Deploy: supabase functions deploy admin-create-user

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: { 'content-type': 'application/json', ...CORS, ...(init.headers ?? {}) },
  });
}

function generatePassword(len = 12): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789@#$!';
  const arr = crypto.getRandomValues(new Uint8Array(len));
  return Array.from(arr, (b) => chars[b % chars.length]).join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, { status: 405 });

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) return json({ error: 'unauthorized' }, { status: 401 });

  const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
  const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
  const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // Verify caller is an admin using their JWT.
  const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user: caller } } = await callerClient.auth.getUser();
  if (!caller) return json({ error: 'unauthorized' }, { status: 401 });

  const { data: callerProfile } = await callerClient
    .from('profiles')
    .select('role')
    .eq('id', caller.id)
    .single();
  if (!callerProfile || callerProfile.role !== 'admin') {
    return json({ error: 'admin_only' }, { status: 403 });
  }

  let payload: any;
  try { payload = await req.json(); } catch { return json({ error: 'bad_json' }, { status: 400 }); }

  const { email, display_name, phone, role, vendor_id } = payload ?? {};

  if (!email || typeof email !== 'string') return json({ error: 'email_required' }, { status: 400 });
  if (!role || !['vendor', 'delivery'].includes(role)) return json({ error: 'role_must_be_vendor_or_delivery' }, { status: 400 });
  if (role === 'vendor' && !vendor_id) return json({ error: 'vendor_id_required_for_vendor_role' }, { status: 400 });

  // Use service_role client to create the user.
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const password = generatePassword(14);

  const { data: newUser, error: createErr } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: display_name || email.split('@')[0] },
  });

  if (createErr) {
    return json({ error: 'create_failed', message: createErr.message }, { status: 400 });
  }

  const userId = newUser.user.id;

  // Update profile role and display name.
  await adminClient
    .from('profiles')
    .update({
      role,
      display_name: display_name || email.split('@')[0],
      phone: phone || null,
    })
    .eq('id', userId);

  // Role-specific setup.
  if (role === 'vendor') {
    await adminClient
      .from('vendor_members')
      .insert({ vendor_id, user_id: userId, role: 'owner' });
  }

  if (role === 'delivery') {
    await adminClient
      .from('delivery_partner_profiles')
      .upsert({
        user_id: userId,
        status: 'approved',
        vehicle_type: 'bike',
        vehicle_number: '',
      }, { onConflict: 'user_id' });
  }

  // Audit log.
  await adminClient.from('admin_audit_logs').insert({
    actor_id: caller.id,
    action: `created_${role}_user`,
    entity_type: 'profile',
    entity_id: userId,
    reason: `Auto-created ${role} account for ${email}`,
  });

  return json({
    user_id: userId,
    email,
    password,
    role,
    display_name: display_name || email.split('@')[0],
  });
});
