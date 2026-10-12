import { supabase } from './supabase';

export type RouteResult =
  | { ok: true; distance_km: number; duration_sec: number | null; provider: 'google' }
  | { ok: false; error: string; message?: string };

/** Preview-only. Calls the `route-distance` Edge Function. */
export async function fetchRouteDistance(
  originLat: number, originLng: number,
  destLat: number, destLng: number
): Promise<RouteResult> {
  const { data, error } = await supabase.functions.invoke('route-distance', {
    body: { originLat, originLng, destLat, destLng },
  });
  if (error) {
    return { ok: false, error: 'routing_failed', message: error.message };
  }
  if (!data || data.error) {
    return { ok: false, error: data?.error ?? 'routing_failed', message: data?.message };
  }
  return { ok: true, distance_km: data.distance_km, duration_sec: data.duration_sec, provider: 'google' };
}

export type PlaceOrderResult =
  | { ok: true; order_id: string; distance_km: number; provider: string }
  | { ok: false; error: string; message?: string };

/** Server-authoritative order placement. */
export async function placeOrder(input: {
  vendor_id: string;
  dest_address: string;
  dest_lat: number;
  dest_lng: number;
  items: { product_id: string; quantity: number; options?: unknown[] }[];
  customer_note?: string | null;
}): Promise<PlaceOrderResult> {
  const { data, error } = await supabase.functions.invoke('place-order', { body: input });
  if (error) return { ok: false, error: 'invoke_failed', message: error.message };
  if (!data || data.error) return { ok: false, error: data?.error ?? 'failed', message: data?.message };
  return { ok: true, order_id: data.order_id, distance_km: data.distance_km, provider: data.provider };
}
