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
  const [loadErr, setLoadErr] = useState<string | null>(null);

  async function load() {
    try {
      // Try the views first, fall back to direct counts
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
        // Views might not exist — build overview from direct queries
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
          in_delivery: orders.filter((o: any) => o.status === 'picked_up' || o.status === 'in_transit').length,
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
    <div>
      <h1 className="text-xl font-bold md:text-2xl">Overview</h1>
      <p className="mt-1 text-xs text-neutral-500 md:text-sm">Today's activity. Live updates via realtime.</p>

      {loadErr && (
        <div className="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200">
          {loadErr}
          <button onClick={load} className="ml-2 font-bold underline">Retry</button>
        </div>
      )}

      <div className="mt-4 grid grid-cols-2 gap-2 md:mt-5 md:gap-3 lg:grid-cols-4">
        <Tile label="Orders today" value={data?.orders_today ?? 0} icon={<ShoppingBag size={16} />} />
        <Tile label="Collections" value={data ? formatRupees(data.collected_paise) : '₹0'} icon={<Wallet size={16} />} hint="Verified only" />
        <Tile label="Gross value" value={data ? formatRupees(data.gov_paise) : '₹0'} icon={<Wallet size={16} />} hint="All orders today" />
        <Tile label="Awaiting pay" value={data?.awaiting_payment ?? 0} icon={<Clock size={16} />} tone="amber" />
        <Tile label="Preparing" value={data?.preparing ?? 0} icon={<Clock size={16} />} />
        <Tile label="In delivery" value={data?.in_delivery ?? 0} icon={<Bike size={16} />} />
        <Tile label="Delivered" value={data?.delivered_today ?? 0} icon={<CheckCircle2 size={16} />} tone="green" />
        <Tile label="Cancelled" value={data?.cancelled_today ?? 0} icon={<XCircle size={16} />} tone="red" />
      </div>

      <div className="mt-4 grid gap-3 md:grid-cols-2">
        <section className="card p-3 md:p-4">
          <div className="flex items-center justify-between">
            <div className="text-xs font-semibold md:text-sm">Top vendors today</div>
            <Store size={14} className="text-neutral-400" />
          </div>
          <div className="mt-2 divide-y divide-neutral-200 dark:divide-neutral-800">
            {vendorSales.length === 0 && <div className="py-3 text-xs text-neutral-500">No sales yet today.</div>}
            {vendorSales.map((v) => (
              <div key={v.vendor_id} className="flex items-center justify-between py-2 text-xs md:text-sm">
                <div>
                  <div className="font-medium">{v.name}</div>
                  <div className="text-[11px] text-neutral-500">{v.orders} orders</div>
                </div>
                <div className="font-semibold">{formatRupees(v.collected_paise)}</div>
              </div>
            ))}
          </div>
        </section>

        <section className="card p-3 md:p-4">
          <div className="flex items-center justify-between">
            <div className="text-xs font-semibold md:text-sm">Recent orders</div>
            <ShoppingBag size={14} className="text-neutral-400" />
          </div>
          <div className="mt-2 divide-y divide-neutral-200 dark:divide-neutral-800">
            {recent.length === 0 && <div className="py-3 text-xs text-neutral-500">No orders yet.</div>}
            {recent.map((o) => (
              <div key={o.id} className="flex items-center justify-between py-2 text-xs md:text-sm">
                <div>
                  <div className="font-medium">#{o.order_number}</div>
                  <div className="text-[11px] text-neutral-500">{o.vendors?.name}</div>
                </div>
                <div className="text-right">
                  <div className="text-[11px]">{String(o.status).replaceAll('_', ' ')}</div>
                  <div className="font-semibold">{formatRupees(o.total_payable_paise)}</div>
                </div>
              </div>
            ))}
          </div>
        </section>
      </div>

      <section className="card mt-3 p-3 md:mt-4 md:p-4">
        <div className="flex items-center gap-2 text-xs font-semibold md:text-sm"><Users size={14} /> Platform</div>
        <div className="mt-2 grid grid-cols-3 gap-2 text-xs md:text-sm">
          <StatLine k="Customers" v={data?.customers_total ?? 0} />
          <StatLine k="Active vendors" v={data?.vendors_active ?? 0} />
          <StatLine k="Delivery partners" v={data?.partners_active ?? 0} />
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
    <div className={`card p-3 md:p-4 ${toneCls[tone]}`}>
      <div className="flex items-center justify-between text-neutral-500">
        <div className="text-[10px] font-semibold uppercase tracking-wider md:text-xs">{label}</div>
        {icon}
      </div>
      <div className="mt-1 text-lg font-bold md:text-xl">{value}</div>
      {hint && <div className="mt-0.5 text-[10px] text-neutral-400">{hint}</div>}
    </div>
  );
}

function StatLine({ k, v }: { k: string; v: React.ReactNode }) {
  return (
    <div>
      <div className="text-[11px] text-neutral-500">{k}</div>
      <div className="mt-0.5 text-base font-bold md:text-lg">{v}</div>
    </div>
  );
}
