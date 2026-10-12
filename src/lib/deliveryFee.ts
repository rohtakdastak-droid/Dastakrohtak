// Client mirror of calc_delivery_fee_paise. SERVER is authoritative — this is
// only for display during checkout. The final fee is always recomputed on insert.

export type RateBand = { min_km: number; max_km: number; fee_paise: number };

export const DEFAULT_BANDS: RateBand[] = [
  { min_km: 0, max_km: 1.0, fee_paise: 1500 },
  { min_km: 1.0, max_km: 1.5, fee_paise: 2000 },
  { min_km: 1.5, max_km: 2.0, fee_paise: 2500 },
  { min_km: 2.0, max_km: 2.5, fee_paise: 2700 },
  { min_km: 2.5, max_km: 3.0, fee_paise: 3300 },
  { min_km: 3.0, max_km: 3.5, fee_paise: 3700 },
  { min_km: 3.5, max_km: 4.0, fee_paise: 4400 },
  { min_km: 4.0, max_km: 4.5, fee_paise: 4700 },
  { min_km: 4.5, max_km: 5.0, fee_paise: 5500 },
  { min_km: 5.0, max_km: 5.5, fee_paise: 5700 },
  { min_km: 5.5, max_km: 6.0, fee_paise: 6300 },
  { min_km: 6.0, max_km: 6.5, fee_paise: 6700 },
  { min_km: 6.5, max_km: 7.0, fee_paise: 7300 },
  { min_km: 7.0, max_km: 7.5, fee_paise: 7700 },
  { min_km: 7.5, max_km: 8.0, fee_paise: 8300 },
  { min_km: 8.0, max_km: 8.5, fee_paise: 8700 },
  { min_km: 8.5, max_km: 9.0, fee_paise: 9000 },
];

export const OVERFLOW = { ceiling_km: 9.0, base_fee_paise: 9000, per_km_paise: 500 };

export function calcDeliveryFeePaise(distanceKm: number, bands = DEFAULT_BANDS): number {
  if (distanceKm == null || distanceKm < 0) return 0;
  // Floating-point tolerance for boundary comparisons.
  const EPS = 1e-6;
  if (distanceKm <= EPS) return bands[0].fee_paise;

  if (distanceKm <= OVERFLOW.ceiling_km + EPS) {
    for (const b of bands) {
      if (distanceKm > b.min_km + EPS && distanceKm <= b.max_km + EPS) {
        return b.fee_paise;
      }
    }
    return bands[bands.length - 1].fee_paise;
  }

  const extraKm = Math.ceil(distanceKm - OVERFLOW.ceiling_km - EPS);
  return OVERFLOW.base_fee_paise + extraKm * OVERFLOW.per_km_paise;
}

export function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const toRad = (x: number) => (x * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function formatRupees(paise: number): string {
  return '₹' + (paise / 100).toLocaleString('en-IN', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
}
