import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Navigation, Package, Truck, CheckCircle2, MapPin, FileText } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatRupees } from '../../lib/deliveryFee';

type Active = {
  assignment_id: string;
  order_id: string;
  order_number: string;
  status: string;
  vendor_name: string;
  pickup_address: string; pickup_lat: number; pickup_lng: number;
  destination_address: string; destination_lat: number; destination_lng: number;
  delivery_distance_km: number;
  delivery_fee_paise: number;
  items_subtotal_paise: number;
  item_count: number;
  customer_note: string | null;
};

export default function Active() {
  const [cur, setCur] = useState<Active | null>(null);
  const [loading, setLoading] = useState(true);
  const [arrived, setArrived] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function load() {
    const { data } = await supabase.rpc('my_active_delivery');
    const row = (data as Active[])?.[0] ?? null;
    setCur(row);
    setLoading(false);
  }

  useEffect(() => {
    load();
    const ch = supabase
      .channel('partner:active')
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'orders' }, load)
      .subscribe();
    return () => void supabase.removeChannel(ch);
  }, []);

  async function advance(next: 'picked_up' | 'out_for_delivery' | 'delivered') {
    setBusy(true);
    setErr(null);
    const { error } = await supabase.rpc('partner_set_order_status', {
      p_order_id: cur!.order_id,
      p_new: next,
    });
    setBusy(false);
    if (error) setErr(error.message);
    else load();
  }

  if (loading) return <div className="p-6 text-sm text-neutral-500">Loading…</div>;

  if (!cur) {
    return (
      <div>
        <h1 className="text-xl font-bold">Active delivery</h1>
        <div className="card mt-4 p-6 text-center text-sm text-neutral-500">
          No active delivery. <Link to="/partner" className="font-semibold text-brand-600">See available orders →</Link>
        </div>
      </div>
    );
  }

  const nav = (lat: number, lng: number) =>
    `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}&travelmode=driving`;

  return (
    <div>
      <h1 className="text-xl font-bold">Active delivery</h1>
      <div className="mt-1 text-xs text-neutral-500">
        #{cur.order_number} · {cur.status.replaceAll('_', ' ')}
      </div>

      <section className="card mt-4 p-4">
        <div className="flex items-start justify-between">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wider text-emerald-600">Pickup</div>
            <div className="mt-1 font-semibold">{cur.vendor_name}</div>
            <div className="text-xs text-neutral-500">{cur.pickup_address}</div>
          </div>
          <a className="btn-outline" href={nav(cur.pickup_lat, cur.pickup_lng)} target="_blank" rel="noreferrer">
            <Navigation size={14} /> Nav
          </a>
        </div>
      </section>

      <section className="card mt-3 p-4">
        <div className="flex items-start justify-between">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wider text-rose-600">Drop</div>
            <div className="mt-1 text-xs text-neutral-500">{cur.destination_address}</div>
            <div className="mt-1 text-[11px] text-neutral-400">
              <MapPin size={10} className="inline" /> {cur.destination_lat}, {cur.destination_lng}
            </div>
          </div>
          <a className="btn-outline" href={nav(cur.destination_lat, cur.destination_lng)} target="_blank" rel="noreferrer">
            <Navigation size={14} /> Nav
          </a>
        </div>
      </section>

      <section className="card mt-3 p-4 text-sm">
        <div className="flex items-center gap-2 font-semibold"><FileText size={14} /> Order</div>
        <div className="mt-1 flex justify-between text-neutral-500">
          <span>{cur.item_count} item(s)</span>
          <span>{Number(cur.delivery_distance_km).toFixed(2)} km</span>
        </div>
        {cur.customer_note && (
          <div className="mt-2 rounded-lg bg-neutral-50 p-2 text-xs italic dark:bg-neutral-900">
            Customer note: “{cur.customer_note}”
          </div>
        )}
        <div className="mt-3 flex justify-between text-xs text-neutral-500">
          <span>Order value</span>
          <span>{formatRupees(cur.items_subtotal_paise)}</span>
        </div>
        <div className="mt-1 flex justify-between font-semibold">
          <span>Your earning</span>
          <span className="text-brand-600">{formatRupees(cur.delivery_fee_paise)}</span>
        </div>
      </section>

      {err && <div className="mt-3 rounded-xl bg-red-50 p-3 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200">{err}</div>}

      <div className="mt-5 space-y-2">
        {cur.status === 'assigned' && (
          <>
            {!arrived ? (
              <button className="btn-outline w-full" onClick={() => setArrived(true)}>
                <MapPin size={16} /> I've arrived at pickup
              </button>
            ) : (
              <button className="btn-primary w-full" disabled={busy} onClick={() => advance('picked_up')}>
                <Package size={16} /> Confirm pickup
              </button>
            )}
          </>
        )}
        {cur.status === 'picked_up' && (
          <button className="btn-primary w-full" disabled={busy} onClick={() => advance('out_for_delivery')}>
            <Truck size={16} /> Start delivery
          </button>
        )}
        {cur.status === 'out_for_delivery' && (
          <button className="btn-primary w-full" disabled={busy} onClick={() => advance('delivered')}>
            <CheckCircle2 size={16} /> Mark delivered
          </button>
        )}
      </div>
    </div>
  );
}
