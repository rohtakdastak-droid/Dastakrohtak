import { useEffect, useState, useRef } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { MapPin, AlertTriangle, RefreshCw, Navigation, Shield, ArrowRight, Crosshair } from 'lucide-react';
import { MapContainer, TileLayer, Marker, useMapEvents, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { useCart } from '../lib/cart';
import { calcDeliveryFeePaise, formatRupees } from '../lib/deliveryFee';
import { supabase, type Vendor } from '../lib/supabase';
import { useSession } from '../lib/auth';
import { fetchRouteDistance, placeOrder } from '../lib/routing';

// Fix default marker icon (Leaflet + bundler issue)
delete (L.Icon.Default.prototype as any)._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon-2x.png',
  iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png',
});

function MapClickHandler({ onMove }: { onMove: (lat: number, lng: number) => void }) {
  useMapEvents({
    click(e) { onMove(e.latlng.lat, e.latlng.lng); },
  });
  return null;
}

function FlyTo({ lat, lng }: { lat: number; lng: number }) {
  const map = useMap();
  useEffect(() => { map.flyTo([lat, lng], 16, { duration: 0.8 }); }, [map, lat, lng]);
  return null;
}

export default function Checkout() {
  const cart = useCart();
  const navigate = useNavigate();
  const { session } = useSession();
  const [vendor, setVendor] = useState<Vendor | null>(null);
  const [addr, setAddr] = useState(() => localStorage.getItem('dastak.address') || '');
  const [lat, setLat] = useState<number | null>(null);
  const [lng, setLng] = useState<number | null>(null);
  const [distance, setDistance] = useState<number | null>(null);
  const [, setProvider] = useState<'google' | 'estimate' | null>(null);
  const [routing, setRouting] = useState(false);
  const [routeErr, setRouteErr] = useState<string | null>(null);
  const [placing, setPlacing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [mapReady, setMapReady] = useState(false);
  const mapRef = useRef<L.Map | null>(null);

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
      setRouteErr(r.message ?? 'Could not compute route. Please retry.');
    }
  }

  useEffect(() => {
    if (vendor && lat != null && lng != null) recalcRoute();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [vendor?.id, lat, lng]);

  const feePaise = distance == null ? null : calcDeliveryFeePaise(distance);
  const subtotal = cart.subtotalPaise();
  const total = subtotal + (feePaise ?? 0);

  function handleMapMove(newLat: number, newLng: number) {
    setLat(newLat);
    setLng(newLng);
    const coordStr = `${newLat.toFixed(5)}, ${newLng.toFixed(5)}`;
    if (!addr || addr.match(/^\d+\.\d+,\s*\d+\.\d+$/)) {
      setAddr(coordStr);
      localStorage.setItem('dastak.address', coordStr);
    }
  }

  function useMyLocation() {
    if (!('geolocation' in navigator)) {
      setError('Location not supported. Enter address manually.');
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const newLat = pos.coords.latitude;
        const newLng = pos.coords.longitude;
        setLat(newLat);
        setLng(newLng);
        const coordStr = `${newLat.toFixed(5)}, ${newLng.toFixed(5)}`;
        if (!addr || addr.match(/^\d+\.\d+,\s*\d+\.\d+$/)) {
          setAddr(coordStr);
          localStorage.setItem('dastak.address', coordStr);
        }
      },
      () => setError('Could not get your location. Tap on the map to set it.')
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
      setError('Please set your delivery location on the map.');
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
      setError(res.message ?? 'Order could not be placed. Please try again.');
      return;
    }

    cart.clear();
    navigate(`/orders/${res.order_id}`);
  }

  // Default center: Rohtak or user's last location
  const defaultLat = lat ?? 28.8955;
  const defaultLng = lng ?? 76.6066;

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
    <div className="page-enter px-4 pb-28 pt-4">
      <h1 className="text-lg font-bold">Checkout</h1>
      {vendor && (
        <div className="mt-0.5 flex items-center gap-1.5 text-xs text-neutral-500">
          <div className="h-1.5 w-1.5 rounded-full bg-brand-500" />
          {vendor.name}
        </div>
      )}

      {/* Delivery location — map + compact address */}
      <div className="card mt-4 overflow-hidden animate-slide-up" style={{ animationDelay: '0ms' }}>
        <div className="relative h-48 w-full bg-neutral-100 dark:bg-neutral-800">
          <MapContainer
            center={[defaultLat, defaultLng]}
            zoom={14}
            className="h-full w-full z-0"
            zoomControl={false}
            attributionControl={false}
            ref={mapRef as any}
            whenReady={() => setMapReady(true)}
          >
            <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
            <MapClickHandler onMove={handleMapMove} />
            {lat != null && lng != null && (
              <>
                <Marker position={[lat, lng]} />
                <FlyTo lat={lat} lng={lng} />
              </>
            )}
          </MapContainer>

          {/* Locate me floating button */}
          <button
            onClick={useMyLocation}
            className="absolute bottom-3 right-3 z-[500] flex h-9 w-9 items-center justify-center rounded-full bg-white shadow-lg transition active:scale-90 dark:bg-neutral-800"
            title="Use my location"
          >
            <Crosshair size={16} className="text-brand-600" />
          </button>

          {!lat && !mapReady && (
            <div className="absolute inset-0 flex items-center justify-center bg-neutral-100/80 dark:bg-neutral-800/80">
              <span className="text-xs text-neutral-500">Loading map…</span>
            </div>
          )}
        </div>

        <div className="px-4 py-3">
          <div className="flex items-center gap-2 text-xs font-semibold text-neutral-500">
            <MapPin size={13} className="text-brand-500" /> Delivery address
          </div>
          <input
            className="mt-1.5 w-full rounded-xl border border-neutral-200 bg-neutral-50 px-3 py-2 text-sm outline-none transition focus:border-brand-400 focus:ring-2 focus:ring-brand-100 dark:border-neutral-700 dark:bg-neutral-800 dark:focus:ring-brand-900"
            placeholder="Full address or tap map"
            value={addr}
            onChange={(e) => {
              setAddr(e.target.value);
              localStorage.setItem('dastak.address', e.target.value);
            }}
          />
          {lat != null && lng != null && (
            <div className="mt-1.5 flex items-center gap-1 text-[11px] text-emerald-600">
              <div className="h-1 w-1 rounded-full bg-emerald-500" />
              {lat.toFixed(5)}, {lng.toFixed(5)}
            </div>
          )}
          {!lat && (
            <div className="mt-1.5 text-[11px] text-neutral-400">
              Tap on the map or use <Navigation size={10} className="inline" /> to set location
            </div>
          )}
        </div>
      </div>

      {/* Bill */}
      <div className="card mt-3 p-4 animate-slide-up" style={{ animationDelay: '80ms', animationFillMode: 'backwards' }}>
        <div className="flex items-center justify-between">
          <div className="text-[10px] font-bold uppercase tracking-widest text-neutral-400">Bill summary</div>
          {routing && (
            <div className="flex items-center gap-1 text-[11px] text-brand-500">
              <RefreshCw size={11} className="animate-spin" /> Computing…
            </div>
          )}
        </div>

        <div className="mt-2 space-y-1.5">
          <Row k="Items subtotal" v={formatRupees(subtotal)} />
          <Row
            k={distance != null ? `Delivery (${distance.toFixed(1)} km)` : 'Delivery fee'}
            v={feePaise == null ? '—' : formatRupees(feePaise)}
          />
          <div className="border-t border-neutral-100 pt-1.5 dark:border-neutral-800" />
          <Row k={<span className="font-bold text-neutral-900 dark:text-neutral-100">Total</span>} v={<span className="text-base font-bold text-neutral-900 dark:text-neutral-100">{formatRupees(total)}</span>} />
        </div>

        {routeErr && (
          <div className="mt-3 flex items-start gap-2 rounded-xl bg-red-50 p-2.5 text-xs text-red-700 dark:bg-red-500/10 dark:text-red-200">
            <AlertTriangle size={13} className="mt-0.5 shrink-0" />
            <div className="flex-1">
              {routeErr}
              <button onClick={recalcRoute} className="ml-2 inline-flex items-center gap-1 font-bold underline">
                <RefreshCw size={11} /> Retry
              </button>
            </div>
          </div>
        )}

        <div className="mt-2.5 flex items-start gap-2 rounded-xl bg-amber-50/80 p-2.5 text-[11px] text-amber-700 dark:bg-amber-500/10 dark:text-amber-200">
          <Shield size={12} className="mt-0.5 shrink-0" />
          Prepaid only. Delivery fee recomputed server-side.
        </div>
      </div>

      {error && (
        <div className="mt-3 animate-scale-in rounded-xl bg-red-50 p-3 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200">{error}</div>
      )}

      <button
        className="btn-primary mt-4 w-full"
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
