import { useEffect, useState } from 'react';
import { Wallet, Clock, CheckCircle2 } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatRupees } from '../../lib/deliveryFee';

type Summary = {
  today_count: number; week_count: number; month_count: number;
  today_paise: number; week_paise: number; month_paise: number;
  pending_paise: number; settled_paise: number;
};

type Row = {
  id: string; order_id: string; gross_paise: number; adjustments_paise: number;
  net_paise: number; settled: boolean; created_at: string;
  orders?: { order_number: string };
};

export default function Earnings() {
  const [s, setS] = useState<Summary | null>(null);
  const [rows, setRows] = useState<Row[]>([]);

  useEffect(() => {
    (async () => {
      const [sum, list] = await Promise.all([
        supabase.rpc('my_earnings_summary'),
        supabase.from('delivery_earnings')
          .select('*,orders(order_number)')
          .order('created_at', { ascending: false })
          .limit(50),
      ]);
      setS(((sum.data as Summary[]) ?? [])[0] ?? null);
      setRows((list.data as unknown as Row[]) ?? []);
    })();
  }, []);

  return (
    <div>
      <h1 className="text-xl font-bold">Earnings</h1>

      <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3">
        <Card label="Today" count={s?.today_count ?? 0} paise={s?.today_paise ?? 0} />
        <Card label="This week" count={s?.week_count ?? 0} paise={s?.week_paise ?? 0} />
        <Card label="This month" count={s?.month_count ?? 0} paise={s?.month_paise ?? 0} />
      </div>

      <div className="mt-3 grid grid-cols-2 gap-2">
        <Mini label="Pending settlement" value={formatRupees(s?.pending_paise ?? 0)} icon={<Clock size={14} />} tone="amber" />
        <Mini label="Already settled" value={formatRupees(s?.settled_paise ?? 0)} icon={<CheckCircle2 size={14} />} tone="green" />
      </div>

      <h2 className="mt-6 text-sm font-semibold uppercase tracking-wider text-neutral-500">Recent deliveries</h2>
      <div className="mt-2 space-y-2">
        {rows.length === 0 && (
          <div className="card p-6 text-center text-sm text-neutral-500">No completed deliveries yet.</div>
        )}
        {rows.map((r) => (
          <div key={r.id} className="card flex items-center justify-between p-3 text-sm">
            <div>
              <div className="font-mono text-xs">#{r.orders?.order_number}</div>
              <div className="text-xs text-neutral-500">{new Date(r.created_at).toLocaleString()}</div>
            </div>
            <div className="text-right">
              <div className="font-semibold">{formatRupees(r.net_paise)}</div>
              <div className="text-[11px] text-neutral-500">{r.settled ? 'Settled' : 'Pending'}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function Card({ label, count, paise }: { label: string; count: number; paise: number }) {
  return (
    <div className="card p-3">
      <div className="flex items-center justify-between text-neutral-500">
        <div className="text-[11px] font-semibold uppercase tracking-wider">{label}</div>
        <Wallet size={14} />
      </div>
      <div className="mt-1 text-lg font-bold">{formatRupees(paise)}</div>
      <div className="text-[11px] text-neutral-500">{count} deliveries</div>
    </div>
  );
}

function Mini({ label, value, icon, tone }: { label: string; value: string; icon: React.ReactNode; tone: 'amber' | 'green' }) {
  const cls = tone === 'amber' ? 'bg-amber-50 dark:bg-amber-500/10' : 'bg-green-50 dark:bg-green-500/10';
  return (
    <div className={`card p-3 ${cls}`}>
      <div className="flex items-center gap-1 text-[11px] font-semibold uppercase tracking-wider text-neutral-600 dark:text-neutral-300">
        {icon} {label}
      </div>
      <div className="mt-1 text-base font-bold">{value}</div>
    </div>
  );
}
