import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Search, X } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatRupees } from '../../lib/deliveryFee';

const STATUSES = [
  'all', 'pending_payment', 'payment_review', 'payment_verified', 'vendor_confirmation',
  'preparing', 'ready_for_pickup', 'assigned', 'picked_up', 'out_for_delivery',
  'delivered', 'rejected', 'cancelled', 'refunded',
] as const;

export default function Orders() {
  const [rows, setRows] = useState<any[]>([]);
  const [status, setStatus] = useState<(typeof STATUSES)[number]>('all');
  const [q, setQ] = useState('');

  async function load() {
    let qry = supabase
      .from('orders')
      .select('id,order_number,status,payment_status,total_payable_paise,created_at,vendor_id,customer_id,vendors(name),profiles:customer_id(display_name)')
      .order('created_at', { ascending: false })
      .limit(100);
    if (status !== 'all') qry = qry.eq('status', status);
    if (q) qry = qry.ilike('order_number', `%${q}%`);
    const { data } = await qry;
    setRows(data ?? []);
  }
  useEffect(() => { load(); }, [status, q]);

  useEffect(() => {
    const ch = supabase
      .channel('admin:orders-list')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'orders' }, load)
      .subscribe();
    return () => void supabase.removeChannel(ch);
    // eslint-disable-next-line
  }, [status, q]);

  async function cancel(id: string) {
    const reason = prompt('Cancellation reason?');
    if (!reason) return;
    const { error } = await supabase.rpc('admin_cancel_order', { p_order_id: id, p_reason: reason });
    if (error) alert(error.message);
    load();
  }

  return (
    <div>
      <h1 className="text-xl font-bold md:text-2xl">Orders</h1>

      <div className="mt-3 flex flex-col gap-2 sm:mt-4 sm:flex-row sm:flex-wrap sm:items-center">
        <div className="relative">
          <Search size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-neutral-400" />
          <input className="input pl-8 w-full sm:w-64" placeholder="Order number…" value={q} onChange={(e) => setQ(e.target.value)} />
        </div>
        <select className="input w-full sm:w-auto" value={status} onChange={(e) => setStatus(e.target.value as any)}>
          {STATUSES.map((s) => <option key={s} value={s}>{s.replaceAll('_', ' ')}</option>)}
        </select>
      </div>

      {/* Mobile card layout */}
      <div className="mt-4 space-y-2 md:hidden">
        {rows.map((o) => (
          <div key={o.id} className="card p-3">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <Link to={`/orders/${o.id}`} className="font-mono text-xs font-bold text-brand-600">#{o.order_number}</Link>
                  <span className="text-xs font-medium capitalize">{String(o.status).replaceAll('_', ' ')}</span>
                </div>
                <div className="mt-1 text-xs text-neutral-500">{o.vendors?.name}</div>
                <div className="text-xs text-neutral-400">{o.profiles?.display_name ?? o.customer_id?.slice(0, 8)}</div>
              </div>
              <div className="text-right shrink-0">
                <div className="text-sm font-bold">{formatRupees(o.total_payable_paise)}</div>
                <div className="text-[10px] text-neutral-400">{o.payment_status}</div>
              </div>
            </div>
            <div className="mt-2 flex items-center justify-between border-t border-neutral-100 pt-2 dark:border-neutral-800">
              <span className="text-[10px] text-neutral-400">{new Date(o.created_at).toLocaleString()}</span>
              {!['delivered', 'cancelled', 'refunded'].includes(o.status) && (
                <button onClick={() => cancel(o.id)} className="flex items-center gap-1 rounded-lg bg-red-50 px-2 py-1 text-xs font-medium text-red-600 dark:bg-red-500/10">
                  <X size={12} /> Cancel
                </button>
              )}
            </div>
          </div>
        ))}
        {rows.length === 0 && <div className="py-6 text-center text-sm text-neutral-500">No orders.</div>}
      </div>

      {/* Desktop table */}
      <div className="mt-4 hidden overflow-x-auto rounded-2xl border border-neutral-200 dark:border-neutral-800 md:block">
        <table className="w-full text-left text-sm">
          <thead className="bg-neutral-50 text-xs uppercase text-neutral-500 dark:bg-neutral-900">
            <tr>
              <th className="px-3 py-2">Order</th>
              <th className="px-3 py-2">Vendor</th>
              <th className="px-3 py-2">Customer</th>
              <th className="px-3 py-2">Status</th>
              <th className="px-3 py-2">Payment</th>
              <th className="px-3 py-2 text-right">Total</th>
              <th className="px-3 py-2">When</th>
              <th className="px-3 py-2 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-neutral-100 dark:divide-neutral-900">
            {rows.map((o) => (
              <tr key={o.id}>
                <td className="px-3 py-2 font-mono text-xs">
                  <Link to={`/orders/${o.id}`} className="text-brand-600 hover:underline">{o.order_number}</Link>
                </td>
                <td className="px-3 py-2">{o.vendors?.name}</td>
                <td className="px-3 py-2 text-xs text-neutral-500">{o.profiles?.display_name ?? o.customer_id?.slice(0, 8)}</td>
                <td className="px-3 py-2 text-xs">{String(o.status).replaceAll('_', ' ')}</td>
                <td className="px-3 py-2 text-xs">{o.payment_status}</td>
                <td className="px-3 py-2 text-right">{formatRupees(o.total_payable_paise)}</td>
                <td className="px-3 py-2 text-xs text-neutral-500">{new Date(o.created_at).toLocaleString()}</td>
                <td className="px-3 py-2 text-right">
                  {!['delivered', 'cancelled', 'refunded'].includes(o.status) && (
                    <button onClick={() => cancel(o.id)} className="btn-ghost text-red-600">
                      <X size={14} /> Cancel
                    </button>
                  )}
                </td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr><td colSpan={8} className="px-3 py-6 text-center text-sm text-neutral-500">No orders.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
