import { useEffect, useState } from 'react';
import { ShoppingBag, Wallet, Clock, CheckCircle2, XCircle, Users, Store, Bike } from 'lucide-react';
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

  async function load() {
    const [o, v, r] = await Promise.all([
      supabase.from('admin_overview_today').select('*').single(),
      supabase.from('admin_vendor_sales_today').select('*').limit(5),
      supabase
        .from('orders')
        .select('id,order_number,status,payment_status,total_payable_paise,created_at,vendors(name)')
        .order('created_at', { ascending: false })
        .limit(8),
    ]);
    setData(o.data as Overview);
    setVendorSales((v.data as VendorSale[]) ?? []);
    setRecent(r.data ?? []);
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
    <div>
      <h1 className="text-2xl font-bold">Overview</h1>
      <p className="mt-1 text-sm text-neutral-500">Today's activity. Live updates via realtime.</p>

      <div className="mt-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Tile label="Orders today" value={data?.orders_today ?? '—'} icon={<ShoppingBag size={18} />} />
        <Tile label="Verified collections" value={data ? formatRupees(data.collected_paise) : '—'} icon={<Wallet size={18} />} hint="Payment verified only" />
        <Tile label="Gross order value" value={data ? formatRupees(data.gov_paise) : '—'} icon={<Wallet size={18} />} hint="All orders today — not profit" />
        <Tile label="Awaiting payment" value={data?.awaiting_payment ?? '—'} icon={<Clock size={18} />} tone="amber" />
        <Tile label="Preparing" value={data?.preparing ?? '—'} icon={<Clock size={18} />} />
        <Tile label="In delivery" value={data?.in_delivery ?? '—'} icon={<Bike size={18} />} />
        <Tile label="Delivered" value={data?.delivered_today ?? '—'} icon={<CheckCircle2 size={18} />} tone="green" />
        <Tile label="Cancelled" value={data?.cancelled_today ?? '—'} icon={<XCircle size={18} />} tone="red" />
      </div>

      <div className="mt-5 grid gap-4 lg:grid-cols-2">
        <section className="card p-4">
          <div className="flex items-center justify-between">
            <div className="text-sm font-semibold">Top vendors today</div>
            <Store size={16} className="text-neutral-400" />
          </div>
          <div className="mt-3 divide-y divide-neutral-200 dark:divide-neutral-800">
            {vendorSales.length === 0 && <div className="py-3 text-sm text-neutral-500">No sales yet today.</div>}
            {vendorSales.map((v) => (
              <div key={v.vendor_id} className="flex items-center justify-between py-2 text-sm">
                <div>
                  <div className="font-medium">{v.name}</div>
                  <div className="text-xs text-neutral-500">{v.orders} orders</div>
                </div>
                <div className="font-semibold">{formatRupees(v.collected_paise)}</div>
              </div>
            ))}
          </div>
        </section>

        <section className="card p-4">
          <div className="flex items-center justify-between">
            <div className="text-sm font-semibold">Recent orders</div>
            <ShoppingBag size={16} className="text-neutral-400" />
          </div>
          <div className="mt-3 divide-y divide-neutral-200 dark:divide-neutral-800">
            {recent.length === 0 && <div className="py-3 text-sm text-neutral-500">No orders yet.</div>}
            {recent.map((o) => (
              <div key={o.id} className="flex items-center justify-between py-2 text-sm">
                <div>
                  <div className="font-medium">#{o.order_number}</div>
                  <div className="text-xs text-neutral-500">{o.vendors?.name}</div>
                </div>
                <div className="text-right">
                  <div className="text-xs">{String(o.status).replaceAll('_', ' ')}</div>
                  <div className="font-semibold">{formatRupees(o.total_payable_paise)}</div>
                </div>
              </div>
            ))}
          </div>
        </section>
      </div>

      <section className="card mt-4 p-4">
        <div className="flex items-center gap-2 text-sm font-semibold"><Users size={16} /> Platform</div>
        <div className="mt-3 grid grid-cols-3 gap-3 text-sm">
          <StatLine k="Customers" v={data?.customers_total ?? '—'} />
          <StatLine k="Active vendors" v={data?.vendors_active ?? '—'} />
          <StatLine k="Active delivery partners" v={data?.partners_active ?? '—'} />
        </div>
      </section>
    </div>
  );
}

function Tile({
  label, value, icon, hint, tone = 'default',
}: { label: string; value: React.ReactNode; icon: React.ReactNode; hint?: string; tone?: 'default' | 'green' | 'red' | 'amber' }) {
  const toneCls: Record<string, string> = {
    default: '',
    green: 'bg-green-50 dark:bg-green-500/10',
    red: 'bg-red-50 dark:bg-red-500/10',
    amber: 'bg-amber-50 dark:bg-amber-500/10',
  };
  return (
    <div className={`card p-4 ${toneCls[tone]}`}>
      <div className="flex items-center justify-between text-neutral-500">
        <div className="text-xs font-semibold uppercase tracking-wider">{label}</div>
        {icon}
      </div>
      <div className="mt-1 text-xl font-bold">{value}</div>
      {hint && <div className="mt-0.5 text-[11px] text-neutral-400">{hint}</div>}
    </div>
  );
}

function StatLine({ k, v }: { k: string; v: React.ReactNode }) {
  return (
    <div>
      <div className="text-xs text-neutral-500">{k}</div>
      <div className="mt-1 text-lg font-bold">{v}</div>
    </div>
  );
}
