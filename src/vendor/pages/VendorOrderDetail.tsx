import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { ArrowLeft, Check, X, Package, ChefHat, MapPin, Clock, Receipt } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatRupees } from '../../lib/deliveryFee';
import { useCurrentVendor } from '../VendorLayout';

const STATUS_META: Record<string, { label: string; color: string }> = {
  pending_payment: { label: 'Pending payment', color: 'bg-amber-100 text-amber-800 dark:bg-amber-500/15 dark:text-amber-200' },
  payment_review: { label: 'Payment review', color: 'bg-amber-100 text-amber-800 dark:bg-amber-500/15 dark:text-amber-200' },
  payment_verified: { label: 'Payment verified', color: 'bg-sky-100 text-sky-800 dark:bg-sky-500/15 dark:text-sky-200' },
  vendor_confirmation: { label: 'Awaiting confirmation', color: 'bg-indigo-100 text-indigo-800 dark:bg-indigo-500/15 dark:text-indigo-200' },
  preparing: { label: 'Preparing', color: 'bg-orange-100 text-orange-800 dark:bg-orange-500/15 dark:text-orange-200' },
  ready_for_pickup: { label: 'Ready for pickup', color: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-500/15 dark:text-emerald-200' },
  assigned: { label: 'Partner assigned', color: 'bg-sky-100 text-sky-800 dark:bg-sky-500/15 dark:text-sky-200' },
  picked_up: { label: 'Picked up', color: 'bg-sky-100 text-sky-800 dark:bg-sky-500/15 dark:text-sky-200' },
  out_for_delivery: { label: 'Out for delivery', color: 'bg-sky-100 text-sky-800 dark:bg-sky-500/15 dark:text-sky-200' },
  delivered: { label: 'Delivered', color: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-500/15 dark:text-emerald-200' },
  rejected: { label: 'Rejected', color: 'bg-red-100 text-red-800 dark:bg-red-500/15 dark:text-red-200' },
  cancelled: { label: 'Cancelled', color: 'bg-neutral-200 text-neutral-700 dark:bg-neutral-700 dark:text-neutral-200' },
};

function statusPill(status: string) {
  const m = STATUS_META[status] ?? { label: status.replaceAll('_', ' '), color: 'bg-neutral-100 text-neutral-700 dark:bg-neutral-800 dark:text-neutral-200' };
  return <span className={`inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold ${m.color}`}>{m.label}</span>;
}

export default function VendorOrderDetail() {
  const { id } = useParams();
  const { vendor } = useCurrentVendor();
  const [order, setOrder] = useState<any>(null);
  const [items, setItems] = useState<any[]>([]);
  const [history, setHistory] = useState<any[]>([]);
  const [acting, setActing] = useState(false);

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
    setActing(true);
    const { error } = await supabase.rpc('vendor_set_order_status', { p_order_id: id, p_new: next, p_reason: reason });
    setActing(false);
    if (error) alert(error.message);
    load();
  }

  if (!order) return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center p-6">
      <div className="h-8 w-8 animate-spin rounded-full border-4 border-brand-200 border-t-brand-600" />
      <div className="mt-3 text-sm font-medium text-neutral-500">Loading order…</div>
    </div>
  );
  if (order.vendor_id !== vendor.id) {
    return (
      <div className="p-6">
        <div className="text-xl font-bold">Order not for this restaurant</div>
        <Link to="/vendor/orders" className="btn-outline mt-3 inline-flex">Back</Link>
      </div>
    );
  }

  return (
    <div className="pb-24">
      <Link to="/vendor/orders" className="inline-flex items-center gap-1 text-sm text-neutral-500">
        <ArrowLeft size={14} /> Orders
      </Link>

      {/* Header */}
      <div className="mt-3 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">#{order.order_number}</h1>
          <div className="mt-1 flex items-center gap-2 text-xs text-neutral-500">
            <Clock size={12} /> {new Date(order.created_at).toLocaleString()}
          </div>
        </div>
        <div className="flex flex-col items-end gap-1">
          {statusPill(order.status)}
          <span className="text-[11px] text-neutral-500">Payment: {order.payment_status}</span>
        </div>
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-2">
        {/* Items card */}
        <section className="card p-4">
          <div className="flex items-center gap-2 text-sm font-semibold">
            <Receipt size={16} className="text-brand-600" /> Items
          </div>
          <div className="mt-3 space-y-2">
            {items.map((i) => (
              <div key={i.id} className="flex justify-between text-sm">
                <span><span className="font-semibold text-brand-600">{i.quantity}×</span> {i.product_name}</span>
                <span className="font-medium">{formatRupees(i.line_total_paise)}</span>
              </div>
            ))}
          </div>
          {order.customer_note && (
            <div className="mt-3 rounded-xl bg-amber-50 p-3 text-xs text-amber-900 dark:bg-amber-500/10 dark:text-amber-200">
              <b>Customer note:</b> {order.customer_note}
            </div>
          )}
          <div className="mt-3 border-t border-neutral-100 pt-3 dark:border-neutral-800">
            <Row k="Items subtotal" v={formatRupees(order.items_subtotal_paise)} />
            <Row k={`Delivery (${Number(order.delivery_distance_km).toFixed(2)} km)`} v={formatRupees(order.delivery_fee_paise)} />
            <div className="mt-2 flex justify-between border-t border-neutral-100 pt-2 text-sm font-bold dark:border-neutral-800">
              <span>Total</span>
              <span className="text-brand-600">{formatRupees(order.total_payable_paise)}</span>
            </div>
          </div>
        </section>

        {/* Delivery + Timeline card */}
        <section className="card p-4">
          <div className="flex items-center gap-2 text-sm font-semibold">
            <MapPin size={16} className="text-brand-600" /> Delivery address
          </div>
          <div className="mt-2 text-sm text-neutral-700 dark:text-neutral-300">{order.destination_address}</div>
          <div className="mt-1 text-[11px] text-neutral-400">
            {Number(order.destination_lat).toFixed(5)}, {Number(order.destination_lng).toFixed(5)}
          </div>

          <div className="mt-5 text-sm font-semibold">Status timeline</div>
          <ul className="mt-3 space-y-3">
            {history.length === 0 && (
              <li className="text-xs text-neutral-400">No history yet.</li>
            )}
            {history.map((h, idx) => (
              <li key={h.id} className="relative flex gap-3 pl-5">
                <span className="absolute left-0 top-1.5 h-2.5 w-2.5 rounded-full bg-brand-500 ring-4 ring-brand-100 dark:ring-brand-500/20" />
                {idx !== history.length - 1 && (
                  <span className="absolute left-[4px] top-4 h-full w-[2px] bg-neutral-200 dark:bg-neutral-800" />
                )}
                <div className="flex flex-1 items-start justify-between">
                  <div className="text-xs font-medium">
                    {STATUS_META[h.new_status]?.label ?? String(h.new_status).replaceAll('_', ' ')}
                  </div>
                  <div className="text-[11px] text-neutral-400">{new Date(h.created_at).toLocaleTimeString()}</div>
                </div>
              </li>
            ))}
          </ul>
        </section>
      </div>

      {/* Action bar */}
      {(order.status === 'vendor_confirmation' || order.status === 'preparing' || order.status === 'ready_for_pickup') && (
        <div className="sticky bottom-0 left-0 right-0 -mx-4 mt-5 border-t border-neutral-200 bg-white/95 p-4 backdrop-blur dark:border-neutral-800 dark:bg-neutral-900/95">
          <div className="flex flex-wrap gap-2">
            {order.status === 'vendor_confirmation' && (
              <>
                <button disabled={acting} className="btn-primary flex-1" onClick={() => act('preparing')}>
                  <Check size={16} /> Accept & start preparing
                </button>
                <button disabled={acting} className="btn-outline text-red-600 hover:border-red-300 hover:bg-red-50 dark:hover:bg-red-500/10" onClick={() => act('rejected')}>
                  <X size={16} /> Reject
                </button>
              </>
            )}
            {order.status === 'preparing' && (
              <button disabled={acting} className="btn-primary flex-1" onClick={() => act('ready_for_pickup')}>
                <Package size={16} /> Mark ready for pickup
              </button>
            )}
            {order.status === 'ready_for_pickup' && (
              <div className="flex w-full items-center justify-center gap-2 rounded-xl bg-amber-50 px-4 py-3 text-sm font-semibold text-amber-800 dark:bg-amber-500/10 dark:text-amber-200">
                <ChefHat size={16} /> Waiting for delivery partner…
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function Row({ k, v }: { k: React.ReactNode; v: React.ReactNode }) {
  return <div className="mt-1 flex justify-between text-sm"><span className="text-neutral-500">{k}</span><span>{v}</span></div>;
}
