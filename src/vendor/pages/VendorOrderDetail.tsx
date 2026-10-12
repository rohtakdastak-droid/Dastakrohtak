import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { ArrowLeft, Check, X, Package, ChefHat } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatRupees } from '../../lib/deliveryFee';
import { useCurrentVendor } from '../VendorLayout';

export default function VendorOrderDetail() {
  const { id } = useParams();
  const { vendor } = useCurrentVendor();
  const [order, setOrder] = useState<any>(null);
  const [items, setItems] = useState<any[]>([]);
  const [history, setHistory] = useState<any[]>([]);

  async function load() {
    const [o, it, h] = await Promise.all([
      supabase.from('orders').select('*').eq('id', id).single(),
      supabase.from('order_items').select('*').eq('order_id', id),
      supabase.from('order_status_history').select('*').eq('order_id', id).order('created_at'),
    ]);
    setOrder(o.data); setItems(it.data ?? []); setHistory(h.data ?? []);
  }

  useEffect(() => {
    load();
    const ch = supabase
      .channel(`vendor-order:${id}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'orders', filter: `id=eq.${id}` }, load)
      .subscribe();
    return () => void supabase.removeChannel(ch);
    // eslint-disable-next-line
  }, [id]);

  async function act(next: 'preparing' | 'ready_for_pickup' | 'rejected') {
    let reason: string | null = null;
    if (next === 'rejected') {
      reason = prompt('Reason for rejecting?');
      if (!reason) return;
    }
    const { error } = await supabase.rpc('vendor_set_order_status', { p_order_id: id, p_new: next, p_reason: reason });
    if (error) alert(error.message);
    load();
  }

  if (!order) return <div className="p-6 text-sm text-neutral-500">Loading…</div>;
  if (order.vendor_id !== vendor.id) {
    return (
      <div className="p-6">
        <div className="text-xl font-bold">Order not for this vendor</div>
        <Link to="/vendor/orders" className="btn-outline mt-3 inline-flex">Back</Link>
      </div>
    );
  }

  return (
    <div>
      <Link to="/vendor/orders" className="inline-flex items-center gap-1 text-sm text-neutral-500">
        <ArrowLeft size={14} /> Orders
      </Link>
      <h1 className="mt-2 text-2xl font-bold">#{order.order_number}</h1>
      <div className="text-xs text-neutral-500">
        {new Date(order.created_at).toLocaleString()} · {String(order.status).replaceAll('_', ' ')} · {order.payment_status}
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <section className="card p-4">
          <div className="text-sm font-semibold">Items</div>
          {items.map((i) => (
            <div key={i.id} className="mt-2 flex justify-between text-sm">
              <span>{i.quantity} × {i.product_name}</span>
              <span>{formatRupees(i.line_total_paise)}</span>
            </div>
          ))}
          {order.customer_note && (
            <div className="mt-3 rounded-lg bg-neutral-50 p-2 text-xs italic dark:bg-neutral-900">
              Customer note: “{order.customer_note}”
            </div>
          )}
          <div className="mt-3 border-t border-neutral-200 pt-2 dark:border-neutral-800" />
          <Row k="Items subtotal" v={formatRupees(order.items_subtotal_paise)} />
          <Row k={`Delivery (${Number(order.delivery_distance_km).toFixed(2)} km)`} v={formatRupees(order.delivery_fee_paise)} />
          <Row k={<b>Total</b>} v={<b>{formatRupees(order.total_payable_paise)}</b>} />
        </section>

        <section className="card p-4">
          <div className="text-sm font-semibold">Delivery</div>
          <div className="mt-1 text-xs text-neutral-500">
            {order.destination_address}
          </div>
          <div className="mt-1 text-[11px] text-neutral-400">
            Pin: {order.destination_lat}, {order.destination_lng}
          </div>

          <div className="mt-4 text-sm font-semibold">History</div>
          <ul className="mt-2 space-y-1 text-xs">
            {history.map((h) => (
              <li key={h.id} className="flex justify-between">
                <span>{String(h.new_status).replaceAll('_', ' ')}</span>
                <span className="text-neutral-500">{new Date(h.created_at).toLocaleTimeString()}</span>
              </li>
            ))}
          </ul>
        </section>
      </div>

      <div className="mt-5 flex flex-wrap gap-2">
        {order.status === 'vendor_confirmation' && (
          <>
            <button className="btn-primary" onClick={() => act('preparing')}><Check size={14} /> Accept</button>
            <button className="btn-outline text-red-600" onClick={() => act('rejected')}><X size={14} /> Reject</button>
          </>
        )}
        {order.status === 'preparing' && (
          <button className="btn-primary" onClick={() => act('ready_for_pickup')}><Package size={14} /> Mark ready</button>
        )}
        {order.status === 'ready_for_pickup' && (
          <div className="chip bg-amber-50 border-amber-500 text-amber-800 dark:bg-amber-500/10 dark:text-amber-200">
            <ChefHat size={12} /> Waiting for delivery partner
          </div>
        )}
      </div>
    </div>
  );
}

function Row({ k, v }: { k: React.ReactNode; v: React.ReactNode }) {
  return <div className="mt-1 flex justify-between text-sm"><span className="text-neutral-500">{k}</span><span>{v}</span></div>;
}
