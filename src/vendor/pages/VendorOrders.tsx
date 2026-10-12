import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { formatRupees } from '../../lib/deliveryFee';
import { useCurrentVendor } from '../VendorLayout';
import { Check, X, ChefHat, Package } from 'lucide-react';

const TABS = [
  { key: 'new', label: 'New', match: ['vendor_confirmation'] },
  { key: 'preparing', label: 'Preparing', match: ['preparing'] },
  { key: 'ready', label: 'Ready', match: ['ready_for_pickup', 'assigned'] },
  { key: 'in_delivery', label: 'In delivery', match: ['picked_up', 'out_for_delivery'] },
  { key: 'done', label: 'Delivered', match: ['delivered'] },
  { key: 'cancelled', label: 'Cancelled', match: ['cancelled', 'rejected', 'refunded'] },
] as const;

export default function VendorOrders() {
  const { vendor } = useCurrentVendor();
  const [params, setParams] = useSearchParams();
  const activeKey = (params.get('filter') ?? 'new') as typeof TABS[number]['key'];
  const active = TABS.find((t) => t.key === activeKey) ?? TABS[0];
  const [orders, setOrders] = useState<any[]>([]);

  async function load() {
    const { data } = await supabase
      .from('orders')
      .select('*,order_items(*)')
      .eq('vendor_id', vendor.id)
      .in('status', active.match as unknown as string[])
      .order('created_at', { ascending: false })
      .limit(50);
    setOrders(data ?? []);
  }

  useEffect(() => {
    load();
    const ch = supabase
      .channel(`vendor-orders:${vendor.id}:${active.key}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'orders', filter: `vendor_id=eq.${vendor.id}` }, load)
      .subscribe();
    return () => void supabase.removeChannel(ch);
    // eslint-disable-next-line
  }, [vendor.id, active.key]);

  async function act(orderId: string, next: 'preparing' | 'ready_for_pickup' | 'rejected') {
    let reason: string | null = null;
    if (next === 'rejected') {
      reason = prompt('Reason for rejecting the order?');
      if (!reason) return;
    }
    const { error } = await supabase.rpc('vendor_set_order_status', {
      p_order_id: orderId,
      p_new: next,
      p_reason: reason,
    });
    if (error) alert(error.message);
    load();
  }

  return (
    <div>
      <h1 className="text-xl font-bold md:text-2xl">Orders</h1>

      <div className="mt-3 flex flex-wrap gap-1.5 md:mt-4 md:gap-2">
        {TABS.map((t) => (
          <button
            key={t.key}
            onClick={() => setParams({ filter: t.key })}
            className={`chip ${activeKey === t.key ? 'border-brand-600 bg-brand-50 text-brand-700 dark:bg-brand-600/10' : ''}`}
          >
            {t.label}
          </button>
        ))}
      </div>

      <div className="mt-4 space-y-3">
        {orders.length === 0 && (
          <div className="card p-6 text-center text-sm text-neutral-500">No orders in this view.</div>
        )}
        {orders.map((o) => (
          <div key={o.id} className="card p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <Link to={`/vendor/orders/${o.id}`} className="font-mono text-xs text-brand-600 hover:underline">
                  #{o.order_number}
                </Link>
                <div className="text-xs text-neutral-500">
                  {new Date(o.created_at).toLocaleString()} · {o.payment_status}
                </div>
                <div className="mt-2 space-y-0.5 text-sm">
                  {o.order_items?.map((i: any) => (
                    <div key={i.id}>{i.quantity} × {i.product_name}</div>
                  ))}
                </div>
                {o.customer_note && (
                  <div className="mt-2 rounded-lg bg-neutral-50 p-2 text-xs italic dark:bg-neutral-900">
                    “{o.customer_note}”
                  </div>
                )}
              </div>
              <div className="text-right">
                <div className="font-semibold">{formatRupees(o.total_payable_paise)}</div>
                <div className="text-[11px] text-neutral-500">{Number(o.delivery_distance_km).toFixed(2)} km</div>
              </div>
            </div>

            <div className="mt-3 flex flex-wrap gap-2">
              {o.status === 'vendor_confirmation' && (
                <>
                  <button className="btn-primary" onClick={() => act(o.id, 'preparing')}>
                    <Check size={14} /> Accept & start preparing
                  </button>
                  <button className="btn-outline text-red-600" onClick={() => act(o.id, 'rejected')}>
                    <X size={14} /> Reject
                  </button>
                </>
              )}
              {o.status === 'preparing' && (
                <button className="btn-primary" onClick={() => act(o.id, 'ready_for_pickup')}>
                  <Package size={14} /> Mark ready for pickup
                </button>
              )}
              {o.status === 'ready_for_pickup' && (
                <div className="chip bg-amber-50 border-amber-500 text-amber-800 dark:bg-amber-500/10 dark:text-amber-200">
                  <ChefHat size={12} /> Waiting for a delivery partner
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
