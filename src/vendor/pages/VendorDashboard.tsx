import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Clock, ShoppingBag, CheckCircle2, XCircle, Wallet, Star } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatRupees } from '../../lib/deliveryFee';
import { useCurrentVendor } from '../VendorLayout';

export default function VendorDashboard() {
  const { vendor } = useCurrentVendor();
  const [stats, setStats] = useState({
    today: 0, newPending: 0, preparing: 0, delivered: 0, cancelled: 0, gross: 0,
  });
  const [recent, setRecent] = useState<any[]>([]);

  async function load() {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const iso = today.toISOString();

    const [all, pending, prep, done, cancelled, verified, rec] = await Promise.all([
      supabase.from('orders').select('id', { count: 'exact', head: true }).eq('vendor_id', vendor.id).gte('created_at', iso),
      supabase.from('orders').select('id', { count: 'exact', head: true }).eq('vendor_id', vendor.id).eq('status', 'vendor_confirmation'),
      supabase.from('orders').select('id', { count: 'exact', head: true }).eq('vendor_id', vendor.id).in('status', ['preparing', 'ready_for_pickup']),
      supabase.from('orders').select('id', { count: 'exact', head: true }).eq('vendor_id', vendor.id).eq('status', 'delivered').gte('created_at', iso),
      supabase.from('orders').select('id', { count: 'exact', head: true }).eq('vendor_id', vendor.id).in('status', ['cancelled', 'rejected']).gte('created_at', iso),
      supabase.from('orders').select('total_payable_paise').eq('vendor_id', vendor.id).eq('payment_status', 'verified').gte('created_at', iso),
      supabase.from('orders').select('id,order_number,status,payment_status,total_payable_paise,created_at').eq('vendor_id', vendor.id).order('created_at', { ascending: false }).limit(8),
    ]);

    setStats({
      today: all.count ?? 0,
      newPending: pending.count ?? 0,
      preparing: prep.count ?? 0,
      delivered: done.count ?? 0,
      cancelled: cancelled.count ?? 0,
      gross: (verified.data ?? []).reduce((s: number, o: any) => s + o.total_payable_paise, 0),
    });
    setRecent(rec.data ?? []);
  }

  useEffect(() => {
    load();
    const ch = supabase
      .channel(`vendor-dash:${vendor.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'orders', filter: `vendor_id=eq.${vendor.id}` }, load)
      .subscribe();
    return () => void supabase.removeChannel(ch);
    // eslint-disable-next-line
  }, [vendor.id]);

  return (
    <div>
      <h1 className="text-2xl font-bold">Dashboard</h1>
      <div className="mt-1 text-sm text-neutral-500">{vendor.name} · today</div>

      <div className="mt-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Tile label="Orders today" value={stats.today} icon={<ShoppingBag size={18} />} />
        <Tile label="New (awaiting you)" value={stats.newPending} icon={<Clock size={18} />} tone="amber"
              link={stats.newPending > 0 ? '/vendor/orders?filter=new' : undefined} />
        <Tile label="Preparing" value={stats.preparing} icon={<Clock size={18} />} />
        <Tile label="Delivered" value={stats.delivered} icon={<CheckCircle2 size={18} />} tone="green" />
        <Tile label="Cancelled / rejected" value={stats.cancelled} icon={<XCircle size={18} />} tone="red" />
        <Tile label="Verified collections" value={formatRupees(stats.gross)} icon={<Wallet size={18} />} />
        <Tile
          label="Rating"
          value={vendor.rating_count ? `${vendor.rating_avg.toFixed(1)} ★` : 'No ratings'}
          icon={<Star size={18} />}
          hint={vendor.rating_count ? `${vendor.rating_count} reviews` : undefined}
        />
      </div>

      <section className="card mt-5 p-4">
        <div className="flex items-center justify-between">
          <div className="text-sm font-semibold">Recent orders</div>
          <Link to="/vendor/orders" className="text-xs text-brand-600 font-semibold">See all →</Link>
        </div>
        <div className="mt-3 divide-y divide-neutral-200 dark:divide-neutral-800">
          {recent.length === 0 && <div className="py-3 text-sm text-neutral-500">No orders yet.</div>}
          {recent.map((o) => (
            <Link key={o.id} to={`/vendor/orders/${o.id}`} className="flex items-center justify-between py-2 text-sm hover:bg-neutral-50 dark:hover:bg-neutral-900">
              <div>
                <div className="font-mono text-xs">#{o.order_number}</div>
                <div className="text-xs text-neutral-500">{String(o.status).replaceAll('_', ' ')} · {o.payment_status}</div>
              </div>
              <div className="font-semibold">{formatRupees(o.total_payable_paise)}</div>
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}

function Tile({ label, value, icon, hint, link, tone = 'default' }:
  { label: string; value: React.ReactNode; icon: React.ReactNode; hint?: string; link?: string; tone?: 'default' | 'green' | 'red' | 'amber' }) {
  const toneCls: Record<string, string> = {
    default: '',
    green: 'bg-green-50 dark:bg-green-500/10',
    red: 'bg-red-50 dark:bg-red-500/10',
    amber: 'bg-amber-50 dark:bg-amber-500/10',
  };
  const inner = (
    <div className={`card p-4 ${toneCls[tone]}`}>
      <div className="flex items-center justify-between text-neutral-500">
        <div className="text-xs font-semibold uppercase tracking-wider">{label}</div>
        {icon}
      </div>
      <div className="mt-1 text-xl font-bold">{value}</div>
      {hint && <div className="mt-0.5 text-[11px] text-neutral-400">{hint}</div>}
    </div>
  );
  return link ? <Link to={link}>{inner}</Link> : inner;
}
