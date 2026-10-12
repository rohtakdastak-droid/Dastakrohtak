import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Receipt, ChevronRight } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useSession } from '../lib/auth';
import { formatRupees } from '../lib/deliveryFee';

type Order = {
  id: string; order_number: string; status: string; payment_status: string;
  total_payable_paise: number; created_at: string; vendor_id: string;
  vendors?: { name: string };
};

function statusBadge(s: string) {
  const label = s.replaceAll('_', ' ');
  if (['delivered'].includes(s)) return <span className="badge-success">{label}</span>;
  if (['cancelled', 'rejected'].includes(s)) return <span className="badge-danger">{label}</span>;
  if (['preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery'].includes(s)) return <span className="badge-warning">{label}</span>;
  return <span className="badge-info">{label}</span>;
}

export default function Orders() {
  const { session, loading } = useSession();
  const [orders, setOrders] = useState<Order[]>([]);
  const [loadingList, setLoadingList] = useState(true);

  useEffect(() => {
    if (!session) return;
    supabase
      .from('orders')
      .select('id,order_number,status,payment_status,total_payable_paise,created_at,vendor_id,vendors(name)')
      .eq('customer_id', session.user.id)
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        setOrders((data as unknown as Order[]) ?? []);
        setLoadingList(false);
      });
  }, [session]);

  if (loading) return <div className="p-6"><div className="skeleton h-8 w-40" /><div className="mt-4 space-y-3">{[1,2,3].map(i=><div key={i} className="skeleton h-24 rounded-2xl" />)}</div></div>;

  if (!session) {
    return (
      <div className="page-enter flex min-h-[60vh] flex-col items-center justify-center p-6 text-center">
        <div className="flex h-20 w-20 items-center justify-center rounded-full bg-neutral-100 dark:bg-neutral-800">
          <Receipt size={32} className="text-neutral-400" />
        </div>
        <h1 className="mt-4 text-lg font-bold">Your orders</h1>
        <p className="mt-1 text-sm text-neutral-500">Sign in to see your order history</p>
        <Link to="/login" className="btn-primary mt-6">Sign in</Link>
      </div>
    );
  }

  return (
    <div className="page-enter p-4 pb-28">
      <h1 className="text-xl font-bold">Your orders</h1>
      {loadingList && <div className="mt-4 space-y-3">{[1,2,3].map(i=><div key={i} className="skeleton h-24 rounded-2xl" />)}</div>}
      {!loadingList && orders.length === 0 && (
        <div className="mt-8 flex flex-col items-center text-center">
          <div className="flex h-20 w-20 items-center justify-center rounded-full bg-neutral-100 dark:bg-neutral-800">
            <Receipt size={32} className="text-neutral-400" />
          </div>
          <div className="mt-4 text-sm font-semibold text-neutral-600 dark:text-neutral-400">No orders yet</div>
          <Link to="/" className="btn-primary mt-4">Browse restaurants</Link>
        </div>
      )}
      <div className="mt-4 space-y-3">
        {orders.map((o, i) => (
          <Link
            key={o.id}
            to={`/orders/${o.id}`}
            className="card group block p-4 transition-all duration-200 hover:shadow-md hover:-translate-y-0.5 animate-slide-up"
            style={{ animationDelay: `${i * 50}ms`, animationFillMode: 'backwards' }}
          >
            <div className="flex items-start justify-between">
              <div>
                <div className="font-bold tracking-tight">{o.vendors?.name ?? 'Order'}</div>
                <div className="mt-0.5 text-xs text-neutral-400">#{o.order_number}</div>
              </div>
              <div className="flex items-center gap-2">
                {statusBadge(o.status)}
                <ChevronRight size={16} className="text-neutral-300 transition group-hover:translate-x-0.5 dark:text-neutral-600" />
              </div>
            </div>
            <div className="mt-3 flex items-center justify-between border-t border-neutral-100 pt-2 dark:border-neutral-800">
              <span className="text-xs text-neutral-400">{new Date(o.created_at).toLocaleString()}</span>
              <span className="text-sm font-bold">{formatRupees(o.total_payable_paise)}</span>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
