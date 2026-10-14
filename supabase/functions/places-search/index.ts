// Address suggestions for signed-in users. The Ola Maps key stays on the server.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { parseSuggestions } from './parse.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization,x-client-info,apikey,content-type',
  'Access-Control-Allow-Methods': 'POST,OPTIONS',
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return reply({});
  if (req.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);
  const key = Deno.env.get('OLA_MAPS_API_KEY')?.trim();
  if (!key) return reply({ error: 'Address search is not configured', suggestions: [] }, 503);
  try {
    const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '');
    const caller = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      auth: { persistSession: false },
    });
    const { data: { user }, error } = await caller.auth.getUser(token);
    if (error || !user) return reply({ error: 'Sign in to search addresses' }, 401);

    const { input, lat, lng } = await req.json();
    const text = typeof input === 'string' ? input.trim() : '';
    if (text.length < 3 || text.length > 120) return reply({ suggestions: [] });
    const query = new URLSearchParams({ input: text, api_key: key });
    if (Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
      query.set('location', `${lat},${lng}`);
      query.set('radius', '30000');
    }
    const res = await fetch(`https://api.olamaps.io/places/v1/autocomplete?${query}`, {
      signal: AbortSignal.timeout(8000),
      headers: { 'X-Request-Id': crypto.randomUUID() },
    });
    if (!res.ok) return reply({ error: 'Address search is temporarily unavailable', suggestions: [] }, 503);
    return reply({ suggestions: parseSuggestions(await res.json()) });
  } catch {
    return reply({ error: 'Address search is temporarily unavailable', suggestions: [] }, 503);
  }
});
