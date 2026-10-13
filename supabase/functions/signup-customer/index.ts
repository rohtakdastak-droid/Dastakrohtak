// Server-side customer signup with email auto-confirmed, so new customers
// log in immediately without needing to click a confirmation link.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization,x-client-info,apikey,content-type',
  'Access-Control-Allow-Methods': 'POST,OPTIONS',
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return reply({});
  if (req.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);
  try {
    const { email, password, display_name, phone } = await req.json();
    if (
      typeof email !== 'string' ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
      typeof password !== 'string' ||
      password.length < 8 ||
      password.length > 100
    ) {
      return reply({ error: 'Enter a valid email and 8-character password' }, 400);
    }
    const name = typeof display_name === 'string' ? display_name.trim().slice(0, 80) : '';
    const tel = typeof phone === 'string' ? phone.replace(/\D/g, '').slice(0, 15) : '';

    const url = Deno.env.get('SUPABASE_URL')!;
    const service = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Create user with email already confirmed.
    const { data: created, error: createError } = await service.auth.admin.createUser({
      email: email.trim().toLowerCase(),
      password,
      email_confirm: true,
      user_metadata: { display_name: name, phone: tel },
    });
    if (createError) {
      const msg = createError.message || 'Signup failed';
      // Nicer wording for the most common case.
      if (/registered|exists/i.test(msg)) {
        return reply({ error: 'An account with this email already exists. Try signing in.' }, 409);
      }
      return reply({ error: msg }, 400);
    }
    const uid = created.user?.id;
    if (uid) {
      // Make sure the profile row has their name, phone and customer role.
      await service.from('profiles').upsert({
        id: uid,
        display_name: name || null,
        phone: tel || null,
        role: 'customer',
      });
    }

    return reply({ ok: true, user_id: uid });
  } catch (error) {
    return reply(
      { error: 'Signup temporarily unavailable. Retry.', detail: String(error) },
      503,
    );
  }
});
