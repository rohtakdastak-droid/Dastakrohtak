import { useEffect, useState, useMemo } from 'react';
import { Link } from 'react-router-dom';
import { MapPin, Search, Leaf, Drumstick, Star, Clock, ChevronRight, Sparkles } from 'lucide-react';
import { supabase, type Vendor, type Product } from '../lib/supabase';
import { formatRupees } from '../lib/deliveryFee';
import NotificationBell from '../components/NotificationBell';

type DietFilter = 'all' | 'veg' | 'non_veg';

export default function Home() {
  const [search, setSearch] = useState('');
  const [dietFilter, setDietFilter] = useState<DietFilter>('all');
  const [vendors, setVendors] = useState<Vendor[]>([]);
  const [products, setProducts] = useState<(Product & { vendor_name?: string })[]>([]);
  const [loading, setLoading] = useState(true);
  const address = localStorage.getItem('dastak.address') || 'Select delivery address';

  useEffect(() => {
    setLoading(true);
    Promise.all([
      supabase
        .from('vendors')
        .select('*')
        .eq('is_active', true)
        .order('sort_priority', { ascending: true }),
      supabase
        .from('products')
        .select('*, vendors!inner(name, is_active)')
        .eq('is_available', true)
        .eq('vendors.is_active', true),
    ]).then(([vendorRes, productRes]) => {
      if (vendorRes.error) console.error(vendorRes.error);
      if (productRes.error) console.error(productRes.error);
      setVendors(vendorRes.data ?? []);
      setProducts(
        (productRes.data ?? []).map((p: any) => ({
          ...p,
          vendor_name: p.vendors?.name,
        }))
      );
      setLoading(false);
    });
  }, []);

  const featured = vendors.filter((v) => v.is_featured);

  const searchLower = search.toLowerCase().trim();

  const matchedProductVendorIds = useMemo(() => {
    if (!searchLower) return new Set<string>();
    return new Set(
      products
        .filter((p) => p.name.toLowerCase().includes(searchLower) || p.description?.toLowerCase().includes(searchLower))
        .map((p) => p.vendor_id)
    );
  }, [searchLower, products]);

  const foodResults = useMemo(() => {
    if (!searchLower) return [];
    return products.filter((p) => {
      const matchesSearch = p.name.toLowerCase().includes(searchLower) || p.description?.toLowerCase().includes(searchLower);
      if (!matchesSearch) return false;
      if (dietFilter === 'veg') return p.diet === 'veg';
      if (dietFilter === 'non_veg') return p.diet === 'non_veg' || p.diet === 'egg';
      return true;
    });
  }, [searchLower, dietFilter, products]);

  const filtered = vendors.filter((v) => {
    if (searchLower) {
      const nameMatch = v.name.toLowerCase().includes(searchLower);
      const foodMatch = matchedProductVendorIds.has(v.id);
      if (!nameMatch && !foodMatch) return false;
    }
    return true;
  });

  return (
    <div className="page-enter">
      {/* Header */}
      <div className="bg-gradient-to-br from-brand-500 via-brand-600 to-brand-700 px-4 pb-8 pt-6 text-white">
        <div className="flex items-center justify-between">
          <Link to="/profile" className="flex min-w-0 items-center gap-2">
            <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-white/20 backdrop-blur">
              <MapPin size={18} />
            </div>
            <div className="min-w-0">
              <div className="text-[10px] font-semibold uppercase tracking-widest text-white/70">
                Deliver to
              </div>
              <div className="flex items-center gap-1 text-sm font-semibold">
                <span className="truncate">{address}</span>
                <ChevronRight size={14} className="shrink-0 text-white/60" />
              </div>
            </div>
          </Link>
          <NotificationBell className="text-white" orderLinkBase="/orders" />
        </div>

        <div className="mt-6">
          <h1 className="text-2xl font-bold tracking-tight">What are you craving?</h1>
          <p className="mt-1 text-sm text-white/70">Order from your favourite restaurants & cafes</p>
        </div>

        <div className="mt-4 relative">
          <Search size={18} className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-neutral-400" />
          <input
            className="w-full rounded-2xl border-0 bg-white px-4 py-3.5 pl-11 text-sm text-neutral-900 shadow-lg placeholder:text-neutral-400 focus:outline-none focus:ring-2 focus:ring-white/50"
            placeholder="Search restaurants, cafes…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>

      <div className="px-4">
        {/* Filters */}
        <div className="mt-4 flex items-center gap-2">
          <button
            onClick={() => setDietFilter((f) => f === 'veg' ? 'all' : 'veg')}
            className={`inline-flex items-center gap-2 rounded-full border px-4 py-2 text-xs font-semibold transition-all ${
              dietFilter === 'veg'
                ? 'border-emerald-500 bg-emerald-50 text-emerald-700 shadow-sm dark:bg-emerald-500/10'
                : 'border-neutral-200 text-neutral-600 dark:border-neutral-800 dark:text-neutral-400'
            }`}
          >
            <Leaf size={14} /> Pure Veg
          </button>
          <button
            onClick={() => setDietFilter((f) => f === 'non_veg' ? 'all' : 'non_veg')}
            className={`inline-flex items-center gap-2 rounded-full border px-4 py-2 text-xs font-semibold transition-all ${
              dietFilter === 'non_veg'
                ? 'border-red-500 bg-red-50 text-red-700 shadow-sm dark:bg-red-500/10'
                : 'border-neutral-200 text-neutral-600 dark:border-neutral-800 dark:text-neutral-400'
            }`}
          >
            <Drumstick size={14} /> Non Veg
          </button>
        </div>

        {/* Featured section */}
        {!search && featured.length > 0 && (
          <div className="mt-6">
            <div className="flex items-center gap-2 text-sm font-bold text-neutral-800 dark:text-neutral-200">
              <Sparkles size={16} className="text-brand-500" /> Featured
            </div>
            <div className="mt-3 flex gap-3 overflow-x-auto pb-2 -mx-4 px-4">
              {featured.map((v) => (
                <Link
                  key={v.id}
                  to={`/vendor/${v.id}`}
                  state={{ vegOnly: dietFilter === 'veg' }}
                  className="group relative min-w-[200px] shrink-0 overflow-hidden rounded-3xl"
                >
                  <div className="h-32 bg-gradient-to-br from-brand-400 to-brand-600 transition-transform duration-300 group-hover:scale-105" />
                  <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent" />
                  <div className="absolute bottom-0 left-0 right-0 p-3 text-white">
                    <div className="font-bold">{v.name}</div>
                    <div className="flex items-center gap-2 text-xs text-white/80">
                      <Clock size={11} /> {v.prep_time_minutes} min
                      {v.rating_count > 0 && (
                        <span className="flex items-center gap-0.5">
                          <Star size={11} fill="currentColor" /> {v.rating_avg.toFixed(1)}
                        </span>
                      )}
                    </div>
                  </div>
                </Link>
              ))}
            </div>
          </div>
        )}

        {/* Food search results */}
        {searchLower && foodResults.length > 0 && (
          <div className="mt-6">
            <div className="text-sm font-bold text-neutral-800 dark:text-neutral-200">
              Food items matching &ldquo;{search}&rdquo;
            </div>
            <div className="mt-3 space-y-2">
              {foodResults.slice(0, 10).map((p) => {
                const price = p.sale_price_paise ?? p.price_paise;
                const dietColor = p.diet === 'veg' ? 'border-emerald-500 bg-emerald-500' : 'border-red-500 bg-red-500';
                return (
                  <Link
                    key={p.id}
                    to={`/vendor/${p.vendor_id}`}
                    state={{ vegOnly: dietFilter === 'veg' }}
                    className="card flex items-center gap-3 p-3"
                  >
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <span className={`inline-block h-3 w-3 rounded border-2 ${dietColor.split(' ')[0]}`}>
                          <span className={`m-[1px] block h-[6px] w-[6px] rounded-full ${dietColor.split(' ')[1]}`} />
                        </span>
                        <span className="text-sm font-bold">{p.name}</span>
                      </div>
                      <div className="mt-0.5 text-xs text-neutral-400">{p.vendor_name}</div>
                    </div>
                    <span className="text-sm font-bold text-brand-600">{formatRupees(price)}</span>
                  </Link>
                );
              })}
            </div>
          </div>
        )}

        {/* All restaurants */}
        <div className="mt-6">
          {!searchLower && (
            <div className="text-sm font-bold text-neutral-800 dark:text-neutral-200">
              All restaurants
            </div>
          )}
          {searchLower && filtered.length > 0 && (
            <div className="text-sm font-bold text-neutral-800 dark:text-neutral-200">
              Restaurants
            </div>
          )}
        </div>

        <div className="mt-3 space-y-3 pb-28">
          {loading && [1, 2, 3].map((i) => (
            <div key={i} className="flex gap-3 rounded-3xl border border-neutral-200/80 bg-white p-3 dark:border-neutral-800/80 dark:bg-neutral-900">
              <div className="h-24 w-24 shrink-0 skeleton rounded-2xl" />
              <div className="flex-1 space-y-2 py-1">
                <div className="skeleton h-4 w-3/4" />
                <div className="skeleton h-3 w-1/2" />
                <div className="skeleton h-3 w-1/3" />
              </div>
            </div>
          ))}
          {!loading && filtered.length === 0 && foodResults.length === 0 && (
            <div className="card p-8 text-center">
              <div className="text-4xl">🍽️</div>
              <div className="mt-2 text-sm font-semibold text-neutral-600 dark:text-neutral-400">No results found</div>
              <div className="mt-1 text-xs text-neutral-400">Try a different search or filter</div>
            </div>
          )}
          {filtered.map((v, i) => (
            <Link
              key={v.id}
              to={`/vendor/${v.id}`}
              state={{ vegOnly: dietFilter === 'veg' }}
              className="card group block overflow-hidden transition-all duration-200 hover:shadow-md hover:-translate-y-0.5 animate-slide-up"
              style={{ animationDelay: `${i * 60}ms`, animationFillMode: 'backwards' }}
            >
              <div className="flex gap-3 p-3">
                <div className="relative h-24 w-24 shrink-0 overflow-hidden rounded-2xl bg-gradient-to-br from-brand-200 to-brand-500 transition-transform duration-300 group-hover:scale-105">
                  {v.rating_count > 0 && (
                    <div className="absolute left-1.5 top-1.5 flex items-center gap-0.5 rounded-lg bg-white/90 px-1.5 py-0.5 text-[11px] font-bold text-emerald-700 backdrop-blur dark:bg-neutral-900/90">
                      <Star size={10} fill="currentColor" className="text-emerald-500" /> {v.rating_avg.toFixed(1)}
                    </div>
                  )}
                </div>
                <div className="flex flex-1 flex-col justify-center">
                  <div className="font-bold tracking-tight">{v.name}</div>
                  <div className="mt-0.5 line-clamp-1 text-xs text-neutral-500">{v.description}</div>
                  <div className="mt-2 flex items-center gap-3 text-xs text-neutral-400">
                    <span className="inline-flex items-center gap-1">
                      <Clock size={12} /> {v.prep_time_minutes} min
                    </span>
                    {v.min_order_paise > 0 && (
                      <span>Min {formatRupees(v.min_order_paise)}</span>
                    )}
                  </div>
                </div>
              </div>
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
}
