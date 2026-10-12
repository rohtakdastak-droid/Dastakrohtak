// supabase/functions/route-distance/index.ts
//
// Computes road-route distance (km) between two coordinates using Google Maps
// Routes API v2. Called from the Checkout screen to preview the delivery fee.
//
// Set the API key in Supabase:
//   supabase secrets set GOOGLE_MAPS_API_KEY=AIza...
// and enable the "Routes API" in your Google Cloud project.
//
// Deploy:
//   supabase functions deploy route-distance

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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, { status: 405 });

  // Require a Supabase JWT so random callers can't burn our quota.
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'unauthorized' }, { status: 401 });

  const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!);
  const { data: identity, error: authError } = await client.auth.getUser(auth.slice(7));
  if (authError || !identity.user) return json({ error: 'unauthorized', message: 'Please sign in to calculate delivery.' }, { status: 401 });
  const key = Deno.env.get('GOOGLE_MAPS_API_KEY') || Deno.env.get('GOOGLE_ROUTES_API_KEY');
  if (!key) {
    return json({ error: 'routing_not_configured', provider: null }, { status: 503 });
  }

  let payload: any;
  try { payload = await req.json(); } catch { return json({ error: 'bad_json' }, { status: 400 }); }

  const { originLat, originLng, destLat, destLng } = payload ?? {};
  for (const v of [originLat, originLng, destLat, destLng]) {
    if (typeof v !== 'number' || !isFinite(v)) {
      return json({ error: 'bad_coords' }, { status: 400 });
    }
  }

  const r = await fetch(
    'https://routes.googleapis.com/directions/v2:computeRoutes',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': key,
        'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration',
      },
      body: JSON.stringify({
        origin: { location: { latLng: { latitude: originLat, longitude: originLng } } },
        destination: { location: { latLng: { latitude: destLat, longitude: destLng } } },
        travelMode: 'DRIVE',
        routingPreference: 'TRAFFIC_UNAWARE',
        units: 'METRIC',
      }),
    }
  );

  if (!r.ok) {
    const text = await r.text();
    return json({ error: 'routing_failed', detail: text }, { status: 502 });
  }
  const data = await r.json();
  const route = data?.routes?.[0];
  if (!route?.distanceMeters) return json({ error: 'no_route' }, { status: 502 });

  const distanceMeters: number = route.distanceMeters;
  const durationSec = parseInt(String(route.duration ?? '').replace('s', ''), 10) || null;

  return json({
    distance_km: distanceMeters / 1000,
    duration_sec: durationSec,
    provider: 'google',
  });
});
