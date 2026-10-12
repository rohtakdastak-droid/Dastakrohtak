import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { MapPin, AlertTriangle, RefreshCw, Navigation, Shield, ArrowRight } from 'lucide-react';
import { useCart } from '../lib/cart';
import { calcDeliveryFeePaise, formatRupees } from '../lib/deliveryFee';
import { supabase, type Vendor } from '../lib/supabase';
import { useSession } from '../lib/auth';
import { fetchRouteDistance, placeOrder } from '../lib/routing';

export default function Checkout() {
  const cart = useCart();
  const navigate = useNavigate();
  const { session } = useSession();
  const [vendor, setVendor] = useState<Vendor | null>(null);
  const [addr, setAddr] = useState(() => localStorage.getItem('dastak.address') || '');
  const [lat, setLat] = useState<number | null>(null);
  const [lng, setLng] = useState<number | null>(null);
  const [distance, setDistance] = useState<number | null>(null);
  const [provider, setProvider] = useState<'google' | null>(null);
  const [routing, setRouting] = useState(false);
  const [routeErr, setRouteErr] = useState<string | null>(null);
  const [placing, setPlacing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!cart.vendorId) return;
    supabase.from('vendors').select('*').eq('id', cart.vendorId).single()
      .then(({ data }) => setVendor(data as Vendor));
  }, [cart.vendorId]);

  async function recalcRoute() {
    if (!vendor || lat == null || lng == null) return;
    setRouting(true);
    setRouteErr(null);
    const r = await fetchRouteDistance(vendor.latitude, vendor.longitude, lat, lng);
    setRouting(false);
    if (r.ok) {
      setDistance(r.distance_km);
      setProvider(r.provider);
    } else {
      setDistance(null);
      setProvider(null);
      setRouteErr(
        r.error === 'routing_not_configured'
          ? 'Delivery routing is not configured yet. Please contact support.'
          : r.error === 'out_of_service_area'
            ? 'This address is outside the service area.'
            : r.message ?? 'Could not compute route. Please retry.'
      );
    }
  }

  useEffect(() => {
    if (vendor && lat != null && lng != null) recalcRoute();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [vendor?.id, lat, lng]);

  const feePaise = distance == null ? null : calcDeliveryFeePaise(distance);
  const subtotal = cart.subtotalPaise();
  const total = subtotal + (feePaise ?? 0);

  function useMyLocation() {
    if (!('geolocation' in navigator)) {
      setError('Location not supported. Enter address manually.');
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLat(pos.coords.latitude);
        setLng(pos.coords.longitude);
        setAddr((prev) => prev || `${pos.coords.latitude.toFixed(5)}, ${pos.coords.longitude.toFixed(5)}`);
        localStorage.setItem('dastak.address', addr || `${pos.coords.latitude.toFixed(5)}, ${pos.coords.longitude.toFixed(5)}`);
      },
      () => setError('Could not get your location. Please enter address manually.')
    );
  }

  async function place() {
    setError(null);
    if (!session) {
      navigate('/login', { state: { redirect: '/checkout' } });
      return;
    }
    if (!cart.vendorId) return;
    if (lat == null || lng == null) {
      setError('Please set your delivery location.');
      return;
    }
    if (routeErr) {
      setError('Please retry routing before placing the order.');
      return;
    }

    setPlacing(true);
    const items = cart.items.map((i) => ({ product_id: i.product_id, quantity: i.quantity, options: i.options ?? [] }));
    const res = await placeOrder({
      vendor_id: cart.vendorId,
      dest_address: addr,
      dest_lat: lat,
      dest_lng: lng,
      items,
      customer_note: null,
    });
    setPlacing(false);

    if (!res.ok) {
      setError(
        res.error === 'routing_not_configured'
          ? 'Delivery routing is not configured. Please contact support.'
          : res.error === 'routing_failed'
            ? 'Could not compute the delivery route. Please retry.'
            : res.error === 'out_of_service_area'
              ? 'This address is outside the service area.'
              : res.message ?? 'Order could not be placed. Please try again.'
      );
      return;
    }

    cart.clear();
    navigate(`/orders/${res.order_id}`);
  }

  if (cart.items.length === 0) {
    return (
      <div className="page-enter flex min-h-[60vh] flex-col items-center justify-center p-6 text-center">
        <div className="text-4xl">🛒</div>
        <div className="mt-3 text-sm text-neutral-500">
          Nothing to check out.{' '}
          <Link to="/" className="font-semibold text-brand-600">Browse →</Link>
        </div>
      </div>
    );
  }

  return (
    <div className="page-enter p-4 pb-28">
      <h1 className="text-xl font-bold">Checkout</h1>
      {vendor && (
        <div className="mt-1 flex items-center gap-2 text-xs text-neutral-500">
          <div className="h-1.5 w-1.5 rounded-full bg-brand-500" />
          {vendor.name}
        </div>
      )}

      {/* Delivery address */}
      <div className="card mt-5 p-5 animate-slide-up" style={{ animationDelay: '0ms' }}>
        <div className="flex items-center gap-2 text-sm font-bold">
          <MapPin size={16} className="text-brand-500" /> Delivery address
        </div>
        <input
          className="input mt-3"
          placeholder="Enter full address"
          value={addr}
          onChange={(e) => {
            setAddr(e.target.value);
            localStorage.setItem('dastak.address', e.target.value);
          }}
        />
        <button onClick={useMyLocation} className="btn-outline mt-3 w-full">
          <Navigation size={14} /> Use my current location
        </button>
        {lat != null && lng != null && (
          <div className="mt-2 flex items-center gap-1 text-xs text-emerald-600">
            <div className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
            Location set: {lat.toFixed(5)}, {lng.toFixed(5)}
          </div>
        )}
      </div>

      {/* Bill */}
      <div className="card mt-4 p-5 animate-slide-up" style={{ animationDelay: '80ms', animationFillMode: 'backwards' }}>
        <div className="flex items-center justify-between">
          <div className="text-xs font-bold uppercase tracking-widest text-neutral-400">Bill summary</div>
          {routing && (
            <div className="flex items-center gap-1 text-xs text-brand-500">
              <RefreshCw size={12} className="animate-spin" /> Computing route…
            </div>
          )}
        </div>

        <div className="mt-3 space-y-2">
          <Row k="Items subtotal" v={formatRupees(subtotal)} />
          <Row
            k={distance != null ? `Delivery (${distance.toFixed(1)} km · ${provider ?? ''})` : 'Delivery fee'}
            v={feePaise == null ? '—' : formatRupees(feePaise)}
          />
          <div className="border-t border-neutral-100 pt-2 dark:border-neutral-800" />
          <Row k={<span className="font-bold text-neutral-900 dark:text-neutral-100">Total</span>} v={<span className="text-base font-bold text-neutral-900 dark:text-neutral-100">{formatRupees(total)}</span>} />
        </div>

        {routeErr && (
          <div className="mt-4 flex items-start gap-2 rounded-2xl bg-red-50 p-3 text-xs text-red-700 dark:bg-red-500/10 dark:text-red-200">
            <AlertTriangle size={14} className="mt-0.5 shrink-0" />
            <div className="flex-1">
              {routeErr}
              <button onClick={recalcRoute} className="ml-2 inline-flex items-center gap-1 font-bold underline">
                <RefreshCw size={12} /> Retry
              </button>
            </div>
          </div>
        )}

        <div className="mt-3 flex items-start gap-2 rounded-2xl bg-amber-50/80 p-3 text-xs text-amber-700 dark:bg-amber-500/10 dark:text-amber-200">
          <Shield size={14} className="mt-0.5 shrink-0" />
          Prepaid only. The delivery fee is recomputed server-side for accuracy.
        </div>
      </div>

      {error && (
        <div className="mt-4 animate-scale-in rounded-2xl bg-red-50 p-4 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200">{error}</div>
      )}

      <button
        className="btn-primary mt-5 w-full"
        disabled={placing || routing || !!routeErr || feePaise == null}
        onClick={place}
      >
        {placing ? 'Placing order…' : `Place order · ${formatRupees(total)}`} <ArrowRight size={16} />
      </button>
    </div>
  );
}

function Row({ k, v }: { k: React.ReactNode; v: React.ReactNode }) {
  return (
    <div className="flex justify-between text-sm">
      <span className="text-neutral-500">{k}</span>
      <span className="font-semibold">{v}</span>
    </div>
  );
}
