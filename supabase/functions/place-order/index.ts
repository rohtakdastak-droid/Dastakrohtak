// supabase/functions/place-order/index.ts
//
// Server-authoritative order placement: recomputes the road-route distance via
// Google Maps Routes API using the vendor's dispatch coordinates (read from the
// DB — not from the client), then calls the `create_order` RPC with the trusted
// distance. The client is never trusted for pricing-critical inputs.
//
// Deploy:
//   supabase functions deploy place-order

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

async function roadDistanceKm(
  key: string,
  originLat: number,
  originLng: number,
  destLat: number,
  destLng: number
): Promise<{ km: number; sec: number | null } | null> {
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
  if (!r.ok) return null;
  const data = await r.json();
  const route = data?.routes?.[0];
  if (!route?.distanceMeters) return null;
  const sec = parseInt(String(route.duration ?? '').replace('s', ''), 10);
  return { km: route.distanceMeters / 1000, sec: Number.isFinite(sec) ? sec : null };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, { status: 405 });

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'unauthorized' }, { status: 401 });

  const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
  const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY');
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) return json({ error: 'misconfigured' }, { status: 500 });

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: identity, error: authError } = await supabase.auth.getUser(auth.slice(7));
  if (authError || !identity.user) return json({ error: 'unauthorized' }, { status: 401 });

  let payload: any;
  try { payload = await req.json(); } catch { return json({ error: 'bad_json' }, { status: 400 }); }

  const {
    vendor_id,
    dest_address,
    dest_lat,
    dest_lng,
    items,
    customer_note,
  } = payload ?? {};

  if (
    typeof vendor_id !== 'string' ||
    typeof dest_address !== 'string' || !dest_address ||
    typeof dest_lat !== 'number' || typeof dest_lng !== 'number' ||
    !Array.isArray(items) || items.length === 0
  ) {
    return json({ error: 'bad_input' }, { status: 400 });
  }

  // Look up the vendor's dispatch coordinates server-side — never trust client.
  const { data: vendor, error: vErr } = await supabase
    .from('vendors')
    .select('id, latitude, longitude, is_active, service_radius_km')
    .eq('id', vendor_id)
    .single();
  if (vErr || !vendor || !vendor.is_active) {
    return json({ error: 'vendor_unavailable' }, { status: 400 });
  }

  // Server-side routing. If Google isn't configured, we refuse rather than
  // silently falling back — the spec requires the user retry or re-enter the
  // address rather than paying based on an invented distance.
  const key = Deno.env.get('GOOGLE_MAPS_API_KEY') || Deno.env.get('GOOGLE_ROUTES_API_KEY');
  let km: number | null = null;
  let provider = 'google';
  if (key) {
    const r = await roadDistanceKm(
      key,
      Number(vendor.latitude), Number(vendor.longitude),
      dest_lat, dest_lng
    );
    if (!r) {
      return json({ error: 'routing_failed', message: 'Could not compute route. Please re-check your address and retry.' }, { status: 502 });
    }
    km = r.km;
  } else {
    return json({ error: 'routing_not_configured', message: 'Delivery routing is not configured. Please contact support.' }, { status: 503 });
  }

  if (km > Number(vendor.service_radius_km)) {
    return json({ error: 'out_of_service_area', km }, { status: 400 });
  }

  const { data: orderId, error: oErr } = await supabase.rpc('create_order', {
    p_vendor_id: vendor_id,
    p_dest_address: dest_address,
    p_dest_lat: dest_lat,
    p_dest_lng: dest_lng,
    p_distance_km: km,
    p_route_provider: provider,
    p_items: items,
    p_customer_note: customer_note ?? null,
  });

  if (oErr) return json({ error: 'create_order_failed', message: oErr.message }, { status: 400 });

  return json({ order_id: orderId, distance_km: km, provider });
});
