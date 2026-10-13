import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ShoppingBag, Wallet, Clock, CheckCircle2, XCircle, Users, Store, Bike, TrendingUp, ArrowRight } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatRupees } from '../../lib/deliveryFee';

type Overview = {
  orders_today: number;
  awaiting_payment: number;
  preparing: number;
  in_delivery: number;
  delivered_today: number;
  cancelled_today: number;
  collected_paise: number;
  gov_paise: number;
  customers_total: number;
  vendors_active: number;
  partners_active: number;
};

type VendorSale = { vendor_id: string; name: string; orders: number; collected_paise: number };

export default function Overview() {
  const [data, setData] = useState<Overview | null>(null);
  const [vendorSales, setVendorSales] = useState<VendorSale[]>([]);
  const [recent, setRecent] = useState<any[]>([]);
  const [loadErr, setLoadErr] = useState<string | null>(null);

  async function load() {
    try {
      const [o, v, r] = await Promise.all([
        supabase.from('admin_overview_today').select('*').single(),
        supabase.from('admin_vendor_sales_today').select('*').limit(5),
        supabase
          .from('orders')
          .select('id,order_number,status,payment_status,total_payable_paise,created_at,vendors(name)')
          .order('created_at', { ascending: false })
          .limit(8),
      ]);

      if (o.error) {
        const today = new Date().toISOString().slice(0, 10);
        const [ordersRes, customersRes, vendorsRes, partnersRes] = await Promise.all([
          supabase.from('orders').select('id,status,payment_status,total_payable_paise').gte('created_at', today),
          supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('role', 'customer'),
          supabase.from('vendors').select('id', { count: 'exact', head: true }).eq('is_active', true),
          supabase.from('delivery_partner_profiles').select('id', { count: 'exact', head: true }).eq('status', 'approved'),
        ]);

        const orders = ordersRes.data ?? [];
        const fallback: Overview = {
          orders_today: orders.length,
          awaiting_payment: orders.filter((o: any) => o.payment_status === 'unpaid').length,
          preparing: orders.filter((o: any) => o.status === 'preparing').length,
          in_delivery: orders.filter((o: any) => o.status === 'picked_up' || o.status === 'in_transit' || o.status === 'out_for_delivery').length,
          delivered_today: orders.filter((o: any) => o.status === 'delivered').length,
          cancelled_today: orders.filter((o: any) => o.status === 'cancelled' || o.status === 'rejected').length,
          collected_paise: orders.filter((o: any) => o.payment_status === 'verified').reduce((s: number, o: any) => s + (o.total_payable_paise ?? 0), 0),
          gov_paise: orders.reduce((s: number, o: any) => s + (o.total_payable_paise ?? 0), 0),
          customers_total: customersRes.count ?? 0,
          vendors_active: vendorsRes.count ?? 0,
          partners_active: partnersRes.count ?? 0,
        };
        setData(fallback);
      } else {
        setData(o.data as Overview);
      }

      setVendorSales((v.data as VendorSale[]) ?? []);
      setRecent(r.data ?? []);
      setLoadErr(null);
    } catch (err: any) {
      setLoadErr(err?.message ?? 'Failed to load dashboard data.');
    }
  }

  useEffect(() => {
    load();
    const ch = supabase
      .channel('admin:orders')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'orders' }, load)
      .subscribe();
    return () => void supabase.removeChannel(ch);
  }, []);

  return (
    <div className="page-enter">
      {/* Hero header */}
      <div className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-brand-500 via-brand-600 to-brand-700 p-5 text-white shadow-lg md:p-7">
        <div className="relative z-10">
          <div className="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-widest text-white/70">
            <span className="h-2 w-2 animate-pulse rounded-full bg-emerald-300" /> Live
          </div>
          <h1 className="mt-1 text-2xl font-bold tracking-tight md:text-3xl">Today's kitchen</h1>
          <p className="mt-1 text-sm text-white/80">Realtime orders, revenue, and operations across all restaurants.</p>

          <div className="mt-5 grid grid-cols-2 gap-3 md:grid-cols-4">
            <HeroStat label="Orders" value={data?.orders_today ?? 0} icon={<ShoppingBag size={14} />} />
            <HeroStat label="Collections" value={data ? formatRupees(data.collected_paise) : '₹0'} icon={<Wallet size={14} />} />
            <HeroStat label="Delivered" value={data?.delivered_today ?? 0} icon={<CheckCircle2 size={14} />} />
            <HeroStat label="In delivery" value={data?.in_delivery ?? 0} icon={<Bike size={14} />} />
          </div>
        </div>
        <div className="absolute -right-10 -top-10 h-40 w-40 rounded-full bg-white/10 blur-3xl" />
        <div className="absolute -bottom-16 -left-8 h-48 w-48 rounded-full bg-amber-300/20 blur-3xl" />
      </div>

      {loadErr && (
        <div className="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200">
          {loadErr}
          <button onClick={load} className="ml-2 font-bold underline">Retry</button>
        </div>
      )}

      {/* Status tiles */}
      <div className="mt-4 grid grid-cols-2 gap-2.5 md:gap-3 lg:grid-cols-4">
        <Tile label="Awaiting pay" value={data?.awaiting_payment ?? 0} icon={<Clock size={16} />} tone="amber" />
        <Tile label="Preparing" value={data?.preparing ?? 0} icon={<Clock size={16} />} tone="orange" />
        <Tile label="Gross value" value={data ? formatRupees(data.gov_paise) : '₹0'} icon={<TrendingUp size={16} />} tone="indigo" hint="All orders today" />
        <Tile label="Cancelled" value={data?.cancelled_today ?? 0} icon={<XCircle size={16} />} tone="red" />
      </div>

      {/* Two-column sections */}
      <div className="mt-4 grid gap-3 md:grid-cols-2">
        <section className="card overflow-hidden p-0">
          <div className="flex items-center justify-between border-b border-neutral-100 bg-gradient-to-r from-amber-50 to-transparent px-4 py-3 dark:border-neutral-800 dark:from-amber-500/5">
            <div className="flex items-center gap-2 text-sm font-bold">
              <Store size={16} className="text-amber-600" /> Top restaurants today
            </div>
            <Link to="/admin/vendors" className="flex items-center gap-0.5 text-[11px] font-semibold text-brand-600">
              View all <ArrowRight size={11} />
            </Link>
          </div>
          <div className="divide-y divide-neutral-100 dark:divide-neutral-800">
            {vendorSales.length === 0 && (
              <div className="p-5 text-center text-xs text-neutral-500">No sales yet today.</div>
            )}
            {vendorSales.map((v, i) => (
              <div key={v.vendor_id} className="flex items-center gap-3 px-4 py-3">
                <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-brand-500 to-brand-700 text-xs font-bold text-white">
                  #{i + 1}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-semibold">{v.name}</div>
                  <div className="text-[11px] text-neutral-500">{v.orders} order{v.orders === 1 ? '' : 's'}</div>
                </div>
                <div className="text-sm font-bold text-brand-600">{formatRupees(v.collected_paise)}</div>
              </div>
            ))}
          </div>
        </section>

        <section className="card overflow-hidden p-0">
          <div className="flex items-center justify-between border-b border-neutral-100 bg-gradient-to-r from-brand-50 to-transparent px-4 py-3 dark:border-neutral-800 dark:from-brand-500/5">
            <div className="flex items-center gap-2 text-sm font-bold">
              <ShoppingBag size={16} className="text-brand-600" /> Recent orders
            </div>
            <Link to="/admin/orders" className="flex items-center gap-0.5 text-[11px] font-semibold text-brand-600">
              View all <ArrowRight size={11} />
            </Link>
          </div>
          <div className="divide-y divide-neutral-100 dark:divide-neutral-800">
            {recent.length === 0 && (
              <div className="p-5 text-center text-xs text-neutral-500">No orders yet.</div>
            )}
            {recent.map((o) => (
              <Link
                key={o.id}
                to={`/orders/${o.id}`}
                className="flex items-center gap-3 px-4 py-3 transition hover:bg-neutral-50 dark:hover:bg-neutral-900"
              >
                <div className="min-w-0 flex-1">
                  <div className="font-mono text-xs font-bold text-brand-600">#{o.order_number}</div>
                  <div className="truncate text-xs text-neutral-500">{o.vendors?.name}</div>
                </div>
                <div className="text-right">
                  <div className="text-xs font-semibold capitalize">{String(o.status).replaceAll('_', ' ')}</div>
                  <div className="text-sm font-bold">{formatRupees(o.total_payable_paise)}</div>
                </div>
              </Link>
            ))}
          </div>
        </section>
      </div>

      {/* Platform footer card */}
      <section className="card mt-3 overflow-hidden p-0">
        <div className="flex items-center gap-2 border-b border-neutral-100 bg-neutral-50 px-4 py-3 text-sm font-bold dark:border-neutral-800 dark:bg-neutral-900">
          <Users size={16} className="text-neutral-500" /> Platform
        </div>
        <div className="grid grid-cols-3">
          <PlatformStat k="Customers" v={data?.customers_total ?? 0} />
          <PlatformStat k="Restaurants" v={data?.vendors_active ?? 0} divider />
          <PlatformStat k="Partners" v={data?.partners_active ?? 0} divider />
        </div>
      </section>
    </div>
  );
}

function HeroStat({ label, value, icon }: { label: string; value: React.ReactNode; icon: React.ReactNode }) {
  return (
    <div className="rounded-2xl bg-white/15 p-3 backdrop-blur">
      <div className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-widest text-white/70">
        {icon} {label}
      </div>
      <div className="mt-1 text-lg font-bold md:text-xl">{value}</div>
    </div>
  );
}

function Tile({
  label, value, icon, hint, tone = 'default',
}: { label: string; value: React.ReactNode; icon: React.ReactNode; hint?: string; tone?: 'default' | 'green' | 'red' | 'amber' | 'orange' | 'indigo' }) {
  const toneCls: Record<string, { bg: string; icon: string }> = {
    default: { bg: '', icon: 'text-neutral-500' },
    green: { bg: 'bg-emerald-50 dark:bg-emerald-500/10', icon: 'text-emerald-600' },
    red: { bg: 'bg-red-50 dark:bg-red-500/10', icon: 'text-red-600' },
    amber: { bg: 'bg-amber-50 dark:bg-amber-500/10', icon: 'text-amber-600' },
    orange: { bg: 'bg-orange-50 dark:bg-orange-500/10', icon: 'text-orange-600' },
    indigo: { bg: 'bg-indigo-50 dark:bg-indigo-500/10', icon: 'text-indigo-600' },
  };
  const t = toneCls[tone];
  return (
    <div className={`card p-3 md:p-4 ${t.bg}`}>
      <div className="flex items-center justify-between">
        <div className="text-[10px] font-semibold uppercase tracking-wider text-neutral-500 md:text-xs">{label}</div>
        <span className={t.icon}>{icon}</span>
      </div>
      <div className="mt-1.5 text-lg font-bold md:text-2xl">{value}</div>
      {hint && <div className="mt-0.5 text-[10px] text-neutral-400">{hint}</div>}
    </div>
  );
}

function PlatformStat({ k, v, divider }: { k: string; v: React.ReactNode; divider?: boolean }) {
  return (
    <div className={`px-4 py-3 ${divider ? 'border-l border-neutral-100 dark:border-neutral-800' : ''}`}>
      <div className="text-[11px] text-neutral-500">{k}</div>
      <div className="mt-0.5 text-lg font-bold md:text-xl">{v}</div>
    </div>
  );
}
