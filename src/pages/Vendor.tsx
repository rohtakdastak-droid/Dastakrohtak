import { useEffect, useState } from 'react';
import { useParams, useLocation, Link } from 'react-router-dom';
import { ArrowLeft, Leaf, Drumstick, Plus, Minus, Clock, MapPin, Star, ShoppingBag } from 'lucide-react';
import { supabase, type Vendor as V, type Product } from '../lib/supabase';
import { formatRupees } from '../lib/deliveryFee';
import { useCart } from '../lib/cart';

export default function Vendor() {
  const { id } = useParams();
  const location = useLocation() as { state?: { vegOnly?: boolean } };
  const [vendor, setVendor] = useState<V | null>(null);
  const [products, setProducts] = useState<Product[]>([]);
  type DietFilter = 'all' | 'veg' | 'non_veg';
  const [dietFilter, setDietFilter] = useState<DietFilter>(location.state?.vegOnly ? 'veg' : 'all');
  const [loading, setLoading] = useState(true);
  const cart = useCart();

  useEffect(() => {
    (async () => {
      setLoading(true);
      const [{ data: v }, { data: p }] = await Promise.all([
        supabase.from('vendors').select('*').eq('id', id).single(),
        supabase.from('products').select('*').eq('vendor_id', id!).eq('is_available', true).order('sort_priority'),
      ]);
      setVendor(v as V);
      setProducts((p as Product[]) ?? []);
      setLoading(false);
    })();
  }, [id]);

  const shown = products.filter((p) => {
    if (dietFilter === 'veg') return p.diet === 'veg';
    if (dietFilter === 'non_veg') return p.diet === 'non_veg' || p.diet === 'egg';
    return true;
  });

  if (loading) {
    return (
      <div className="page-enter">
        <div className="h-48 skeleton rounded-none" />
        <div className="space-y-3 p-4">
          {[1, 2, 3].map((i) => <div key={i} className="skeleton h-24 rounded-2xl" />)}
        </div>
      </div>
    );
  }
  if (!vendor) return <div className="p-6 text-center text-neutral-500">Restaurant not found.</div>;

  const dietDot = (d: string) =>
    d === 'veg' ? 'border-emerald-500 bg-emerald-500' :
    d === 'non_veg' ? 'border-red-500 bg-red-500' : 'border-neutral-400 bg-neutral-400';

  return (
    <div className="page-enter pb-28">
      {/* Hero */}
      <div className="relative h-48 bg-gradient-to-br from-brand-400 via-brand-500 to-brand-700">
        <div className="absolute inset-0 bg-gradient-to-t from-black/50 to-transparent" />
        <Link to="/" className="absolute left-4 top-4 z-10 flex h-10 w-10 items-center justify-center rounded-2xl bg-white/90 text-neutral-800 shadow-lg backdrop-blur transition hover:bg-white dark:bg-neutral-900/90 dark:text-neutral-100">
          <ArrowLeft size={18} />
        </Link>
        <div className="absolute bottom-0 left-0 right-0 p-4 text-white">
          <h1 className="text-2xl font-bold tracking-tight">{vendor.name}</h1>
          <div className="mt-1 flex items-center gap-3 text-sm text-white/80">
            {vendor.rating_count > 0 && (
              <span className="flex items-center gap-1 rounded-lg bg-white/20 px-2 py-0.5 text-xs font-bold backdrop-blur">
                <Star size={12} fill="currentColor" className="text-yellow-300" /> {vendor.rating_avg.toFixed(1)}
              </span>
            )}
            <span className="flex items-center gap-1"><Clock size={13} /> {vendor.prep_time_minutes} min</span>
          </div>
        </div>
      </div>

      <div className="px-4 pt-4">
        {vendor.description && (
          <p className="text-sm text-neutral-500">{vendor.description}</p>
        )}
        <div className="mt-1 flex items-center gap-1 text-xs text-neutral-400">
          <MapPin size={12} /> {vendor.dispatch_address}
        </div>

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
          <div className="text-xs text-neutral-400">{shown.length} item{shown.length !== 1 ? 's' : ''}</div>
        </div>
      </div>

      {/* Menu */}
      <div className="mt-4 space-y-3 px-4">
        {shown.length === 0 && (
          <div className="card p-8 text-center">
            <div className="text-3xl">🥗</div>
            <div className="mt-2 text-sm font-semibold text-neutral-500">No items to show</div>
          </div>
        )}
        {shown.map((p, i) => {
          const inCart = cart.items.find((it) => it.product_id === p.id);
          const price = p.sale_price_paise ?? p.price_paise;
          const onSale = p.sale_price_paise != null && p.sale_price_paise < p.price_paise;
          return (
            <div
              key={p.id}
              className="card flex items-start gap-3 p-4 animate-slide-up"
              style={{ animationDelay: `${i * 50}ms`, animationFillMode: 'backwards' }}
            >
              <div className="flex-1">
                <div className="flex items-center gap-2">
                  <span className={`inline-block h-3.5 w-3.5 rounded border-2 ${dietDot(p.diet).split(' ')[0]}`}>
                    <span className={`m-[2px] block h-[7px] w-[7px] rounded-full ${dietDot(p.diet).split(' ')[1]}`} />
                  </span>
                  <span className="font-bold tracking-tight">{p.name}</span>
                </div>
                {p.description && (
                  <div className="mt-1 line-clamp-2 text-xs text-neutral-500">{p.description}</div>
                )}
                <div className="mt-2 flex items-center gap-2">
                  <span className="text-sm font-bold">{formatRupees(price)}</span>
                  {onSale && (
                    <span className="text-xs text-neutral-400 line-through">{formatRupees(p.price_paise)}</span>
                  )}
                </div>
              </div>

              {/* Add / qty control */}
              <div className="shrink-0 pt-1">
                {inCart ? (
                  <div className="flex items-center gap-1 rounded-2xl border-2 border-brand-500 bg-brand-50 px-1 py-0.5 text-sm font-bold text-brand-700 dark:bg-brand-600/10">
                    <button className="flex h-7 w-7 items-center justify-center rounded-xl transition hover:bg-brand-100 dark:hover:bg-brand-600/20" onClick={() => cart.updateQty(p.id, inCart.quantity - 1)}>
                      <Minus size={14} />
                    </button>
                    <span className="w-5 text-center">{inCart.quantity}</span>
                    <button className="flex h-7 w-7 items-center justify-center rounded-xl transition hover:bg-brand-100 dark:hover:bg-brand-600/20" onClick={() => cart.updateQty(p.id, inCart.quantity + 1)}>
                      <Plus size={14} />
                    </button>
                  </div>
                ) : (
                  <button
                    className="flex items-center gap-1 rounded-2xl border-2 border-brand-500 bg-white px-4 py-1.5 text-sm font-bold text-brand-600 transition hover:bg-brand-50 active:scale-95 dark:bg-neutral-900 dark:hover:bg-brand-600/10"
                    onClick={() =>
                      cart.addItem(vendor.id, vendor.name, {
                        product_id: p.id,
                        name: p.name,
                        unit_price_paise: price,
                        quantity: 1,
                        diet: p.diet,
                      })
                    }
                  >
                    ADD
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* Floating cart bar */}
      {cart.items.length > 0 && cart.vendorId === vendor.id && (
        <div className="fixed inset-x-0 bottom-20 z-30 mx-auto max-w-xl animate-slide-up px-4 sm:max-w-2xl">
          <Link
            to="/cart"
            className="flex items-center justify-between rounded-3xl bg-gradient-to-r from-brand-500 to-brand-600 px-5 py-4 text-white shadow-xl shadow-brand-500/30 transition hover:shadow-brand-500/50"
          >
            <div className="flex items-center gap-3">
              <div className="flex h-8 w-8 items-center justify-center rounded-xl bg-white/20">
                <ShoppingBag size={16} />
              </div>
              <div>
                <div className="text-sm font-bold">
                  {cart.items.reduce((n, it) => n + it.quantity, 0)} item{cart.items.reduce((n, it) => n + it.quantity, 0) !== 1 ? 's' : ''}
                </div>
                <div className="text-xs text-white/70">{formatRupees(cart.subtotalPaise())}</div>
              </div>
            </div>
            <span className="font-bold">View cart →</span>
          </Link>
        </div>
      )}

      {/* Single-vendor cart switch dialog */}
      {cart.pendingSwitch && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-4 backdrop-blur-sm sm:items-center animate-fade-in">
          <div className="card w-full max-w-md p-6 animate-slide-up">
            <div className="text-lg font-bold">Replace cart?</div>
            <p className="mt-2 text-sm text-neutral-500">
              You have items from <b>{cart.vendorName}</b>. Adding from{' '}
              <b>{cart.pendingSwitch.vendorName}</b> will clear your current cart.
            </p>
            <div className="mt-5 flex gap-3">
              <button className="btn-outline flex-1" onClick={cart.cancelSwitch}>Cancel</button>
              <button className="btn-primary flex-1" onClick={cart.confirmSwitch}>Switch</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
