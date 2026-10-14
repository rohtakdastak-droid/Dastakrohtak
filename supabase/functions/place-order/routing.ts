// Road distance for delivery fees: Google Routes, then Ola Maps, then a straight-line estimate.
// Every provider result is sanity-checked against the straight-line distance so a bad
// response (wrong units, broken route) can never reach the fee calculation.

export type Point = { lat: number; lng: number };
export type Provider = 'google' | 'ola' | 'haversine';
export type Distance = { km: number; provider: Provider };
type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

const ROAD_FACTOR_ESTIMATE = 1.3;

export function haversineKm(a: Point, b: Point): number {
  const r = 6371;
  const rad = (x: number) => (x * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return r * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/** A road route is never shorter than the straight line, and in a city rarely more than 5x it. */
export function plausibleKm(km: number, straightKm: number): boolean {
  return Number.isFinite(km) && km >= straightKm * 0.95 - 0.05 && km <= Math.max(straightKm * 5, straightKm + 3);
}

export function googleKey(values: (string | undefined)[]): string | undefined {
  return values.map((v) => v?.match(/AIza[A-Za-z0-9_-]{35}/)?.[0]).find(Boolean);
}

const metres = (v: unknown): number => Number(typeof v === 'object' && v !== null ? (v as { value?: unknown }).value : v);

/** Total metres of the first Ola route: sum of legs, or the route total when legs are absent. */
export function olaMetres(body: unknown): number | null {
  const route = (body as { routes?: Array<{ legs?: Array<{ distance?: unknown }>; distance?: unknown }> })?.routes?.[0];
  if (!route) return null;
  if (Array.isArray(route.legs) && route.legs.length > 0) {
    const total = route.legs.reduce((sum, leg) => sum + metres(leg?.distance), 0);
    return Number.isFinite(total) && total >= 0 ? total : null;
  }
  const total = metres(route.distance);
  return Number.isFinite(total) && total >= 0 ? total : null;
}

async function googleKm(key: string, from: Point, to: Point, fetchFn: Fetch, timeoutMs: number): Promise<number | null> {
  const res = await fetchFn('https://routes.googleapis.com/directions/v2:computeRoutes', {
    method: 'POST',
    signal: AbortSignal.timeout(timeoutMs),
    headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': key, 'X-Goog-FieldMask': 'routes.distanceMeters' },
    body: JSON.stringify({
      origin: { location: { latLng: { latitude: from.lat, longitude: from.lng } } },
      destination: { location: { latLng: { latitude: to.lat, longitude: to.lng } } },
      travelMode: 'TWO_WHEELER',
      routingPreference: 'TRAFFIC_UNAWARE',
    }),
  });
  if (!res.ok) return null;
  const meters = Number((await res.json())?.routes?.[0]?.distanceMeters);
  return Number.isFinite(meters) && meters >= 0 ? meters / 1000 : null;
}

async function olaKm(key: string, from: Point, to: Point, fetchFn: Fetch, timeoutMs: number): Promise<number | null> {
  const query = new URLSearchParams({
    origin: `${from.lat},${from.lng}`,
    destination: `${to.lat},${to.lng}`,
    alternatives: 'false',
    steps: 'false',
    overview: 'false',
    api_key: key,
  });
  const res = await fetchFn(`https://api.olamaps.io/routing/v1/directions?${query}`, {
    method: 'POST',
    signal: AbortSignal.timeout(timeoutMs),
    headers: { 'X-Request-Id': crypto.randomUUID() },
  });
  if (!res.ok) return null;
  const m = olaMetres(await res.json());
  return m === null ? null : m / 1000;
}

export async function roadDistance(
  from: Point,
  to: Point,
  opts: { googleKey?: string; olaKey?: string; fetchFn?: Fetch; timeoutMs?: number },
): Promise<Distance> {
  const fetchFn = opts.fetchFn ?? fetch;
  const timeoutMs = opts.timeoutMs ?? 12000;
  const straight = haversineKm(from, to);
  const attempts: Array<[Provider, string | undefined, typeof googleKm]> = [
    ['google', opts.googleKey, googleKm],
    ['ola', opts.olaKey, olaKm],
  ];
  for (const [provider, key, compute] of attempts) {
    if (!key) continue;
    try {
      const km = await compute(key, from, to, fetchFn, timeoutMs);
      if (km !== null && plausibleKm(km, straight)) return { km, provider };
    } catch {
      // Provider unavailable or timed out: try the next one.
    }
  }
  return { km: straight * ROAD_FACTOR_ESTIMATE, provider: 'haversine' };
}
