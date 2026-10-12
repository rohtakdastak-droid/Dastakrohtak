import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL as string;
const anon = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

if (!url || !anon) {
  // Help the developer notice an unconfigured app rather than failing silently.
  // eslint-disable-next-line no-console
  console.warn('[Dastak] Supabase env not set. Create .env.local from .env.example.');
}

export const supabase = createClient(url || 'http://localhost', anon || 'anon', {
  auth: { persistSession: true, autoRefreshToken: true },
});

export type Vendor = {
  id: string;
  name: string;
  slug: string | null;
  category: 'food';
  description: string | null;
  cover_image_path: string | null;
  logo_image_path: string | null;
  dispatch_address: string;
  latitude: number;
  longitude: number;
  min_order_paise: number;
  prep_time_minutes: number;
  is_active: boolean;
  is_featured: boolean;
  sort_priority: number;
  service_radius_km: number;
  rating_avg: number;
  rating_count: number;
};

export type Product = {
  id: string;
  vendor_id: string;
  name: string;
  description: string | null;
  price_paise: number;
  sale_price_paise: number | null;
  image_path: string | null;
  diet: 'veg' | 'non_veg' | 'egg' | 'unknown';
  stock: number | null;
  is_available: boolean;
};
