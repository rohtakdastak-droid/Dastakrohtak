import { supabase } from './supabase';

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * 1.3;
}

async function functionError(error: { message: string; context?: Response }) {
  const messages: Record<string, string> = {
    unauthorized: 'Please sign in again to calculate delivery.',
    routing_not_configured: 'Delivery routing is not configured. Please contact support.',
    no_route: 'No driving route found. Please check your delivery location.',
    routing_failed: 'The routing service is unavailable. Please retry shortly.',
    out_of_service_area: 'This restaurant does not deliver to your location.',
  };
  try {
    const body = await error.context?.json();
    if (body?.error && messages[body.error]) return messages[body.error];
    if (error.context?.status === 401) return messages.unauthorized;
    if (error.context?.status === 404) return 'Delivery service is not deployed yet. Please contact support.';
    if (body?.message) return String(body.message);
  } catch { /* Network or non-JSON response */ }
  return null;
}

export type RouteResult =
  | { ok: true; distance_km: number; duration_sec: number | null; provider: 'google' | 'estimate' }
  | { ok: false; error: string; message?: string };

/** Preview-only. Calls the `route-distance` Edge Function, falls back to Haversine estimate. */
export async function fetchRouteDistance(
  originLat: number, originLng: number,
  destLat: number, destLng: number
): Promise<RouteResult> {
  // Try Edge Function (needs auth) but fall through to Haversine if unavailable
  try {
    const { data: { session } } = await supabase.auth.getSession();
    if (session) {
      const { data, error } = await supabase.functions.invoke('route-distance', {
        body: { originLat, originLng, destLat, destLng },
      });
      if (!error && data && !data.error) {
        return { ok: true, distance_km: data.distance_km, duration_sec: data.duration_sec, provider: 'google' };
      }
    }
  } catch { /* Edge Function unreachable — fall through to estimate */ }
  const km = haversineKm(originLat, originLng, destLat, destLng);
  return { ok: true, distance_km: Math.round(km * 10) / 10, duration_sec: null, provider: 'estimate' };
}

export type PlaceOrderResult =
  | { ok: true; order_id: string; distance_km: number; provider: string }
  | { ok: false; error: string; message?: string };

/** Server-authoritative order placement. Falls back to client-side insert when Edge Function unavailable. */
export async function placeOrder(input: {
  vendor_id: string;
  dest_address: string;
  dest_lat: number;
  dest_lng: number;
  items: { product_id: string; quantity: number; options?: unknown[] }[];
  customer_note?: string | null;
}): Promise<PlaceOrderResult> {
  try {
    const { data, error } = await supabase.functions.invoke('place-order', { body: input });
    if (!error && data && !data.error) {
      return { ok: true, order_id: data.order_id, distance_km: data.distance_km, provider: data.provider };
    }
    const msg = error ? await functionError(error) : data?.message;
    if (msg) return { ok: false, error: data?.error ?? 'invoke_failed', message: msg };
  } catch { /* Edge Function not deployed */ }

  // Fallback: compute distance client-side and insert order directly
  const { data: vendor } = await supabase.from('vendors').select('latitude, longitude, category').eq('id', input.vendor_id).single();
  if (!vendor) return { ok: false, error: 'vendor_not_found', message: 'Restaurant not found.' };

  const km = haversineKm(vendor.latitude, vendor.longitude, input.dest_lat, input.dest_lng);
  const distKm = Math.round(km * 10) / 10;
  const { calcDeliveryFeePaise } = await import('./deliveryFee');
  const feePaise = calcDeliveryFeePaise(km);

  const productIds = input.items.map((i) => i.product_id);
  const { data: products } = await supabase.from('products').select('id, name, price_paise, sale_price_paise').in('id', productIds);
  if (!products) return { ok: false, error: 'products_not_found', message: 'Could not verify product prices.' };

  const prodMap = new Map(products.map((p: any) => [p.id, p]));
  let itemsSubtotalPaise = 0;
  const orderItemRows = input.items.map((i) => {
    const prod = prodMap.get(i.product_id);
    const unitPrice = prod ? (prod.sale_price_paise ?? prod.price_paise) : 0;
    const lineTotal = unitPrice * i.quantity;
    itemsSubtotalPaise += lineTotal;
    return {
      product_id: i.product_id,
      product_name: prod?.name ?? 'Unknown',
      unit_price_paise: unitPrice,
      quantity: i.quantity,
      options: i.options ?? [],
      line_total_paise: lineTotal,
    };
  });

  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return { ok: false, error: 'unauthorized', message: 'Please sign in to place an order.' };

  const { data: order, error: insertErr } = await supabase.from('orders').insert({
    customer_id: session.user.id,
    vendor_id: input.vendor_id,
    category: vendor.category ?? 'restaurant',
    status: 'pending',
    items_subtotal_paise: itemsSubtotalPaise,
    delivery_fee_paise: feePaise,
    delivery_distance_km: distKm,
    delivery_route_provider: 'estimate',
    total_payable_paise: itemsSubtotalPaise + feePaise,
    destination_address: input.dest_address,
    destination_lat: input.dest_lat,
    destination_lng: input.dest_lng,
    customer_note: input.customer_note ?? null,
  }).select('id').single();

  if (insertErr || !order) {
    return { ok: false, error: 'insert_failed', message: insertErr?.message ?? 'Could not create order.' };
  }

  // Insert order items into separate table
  if (orderItemRows.length > 0) {
    await supabase.from('order_items').insert(
      orderItemRows.map((r) => ({ ...r, order_id: order.id }))
    );
  }

  return { ok: true, order_id: order.id, distance_km: distKm, provider: 'estimate' };
}
