import { useEffect, useState } from 'react';
import { Check, X, Download } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatRupees } from '../../lib/deliveryFee';

export default function Payments() {
  const [rows, setRows] = useState<any[]>([]);
  const [tab, setTab] = useState<'submitted' | 'verified' | 'rejected' | 'all'>('submitted');

  async function load() {
    let q = supabase
      .from('payments')
      .select('id,order_id,amount_paise,method,upi_reference,proof_image_path,status,verified_at,rejection_reason,created_at,orders(order_number,vendors(name),customer_id)')
      .order('created_at', { ascending: false })
      .limit(200);
    if (tab !== 'all') q = q.eq('status', tab);
    const { data } = await q;
    setRows(data ?? []);
  }
  useEffect(() => { load(); }, [tab]);

  async function act(id: string, approved: boolean) {
    const reason = approved ? null : prompt('Reason for rejection?');
    if (!approved && !reason) return;
    const { error } = await supabase.rpc('verify_payment', {
      p_payment_id: id,
      p_approved: approved,
      p_reason: reason,
    });
    if (error) alert(error.message);
    load();
  }

  function exportCsv() {
    const header = ['payment_id', 'order_number', 'vendor', 'amount_rupees', 'upi_reference', 'status', 'created_at', 'verified_at'];
    const lines = rows.map((r) =>
      [r.id, r.orders?.order_number, r.orders?.vendors?.name, (r.amount_paise / 100).toFixed(2),
       r.upi_reference ?? '', r.status, r.created_at, r.verified_at ?? ''].map((v) => `"${String(v ?? '').replaceAll('"', '""')}"`).join(',')
    );
    const blob = new Blob([header.join(',') + '\n' + lines.join('\n')], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `dastak-payments-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div>
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Payment ledger</h1>
        <button className="btn-outline" onClick={exportCsv}><Download size={14} /> Export CSV</button>
      </div>

      <div className="mt-4 flex gap-2">
        {(['submitted', 'verified', 'rejected', 'all'] as const).map((t) => (
          <button key={t} onClick={() => setTab(t)} className={`chip capitalize ${tab === t ? 'border-brand-600 bg-brand-50 text-brand-700 dark:bg-brand-600/10' : ''}`}>
            {t}
          </button>
        ))}
      </div>

      <div className="mt-4 overflow-x-auto rounded-2xl border border-neutral-200 dark:border-neutral-800">
        <table className="w-full text-left text-sm">
          <thead className="bg-neutral-50 text-xs uppercase text-neutral-500 dark:bg-neutral-900">
            <tr>
              <th className="px-3 py-2">Order</th>
              <th className="px-3 py-2">Vendor</th>
              <th className="px-3 py-2 text-right">Amount</th>
              <th className="px-3 py-2">Method</th>
              <th className="px-3 py-2">UPI Ref</th>
              <th className="px-3 py-2">Status</th>
              <th className="px-3 py-2">Created</th>
              <th className="px-3 py-2 text-right">Verify</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-neutral-100 dark:divide-neutral-900">
            {rows.map((p) => (
              <tr key={p.id}>
                <td className="px-3 py-2 font-mono text-xs">{p.orders?.order_number}</td>
                <td className="px-3 py-2">{p.orders?.vendors?.name}</td>
                <td className="px-3 py-2 text-right font-semibold">{formatRupees(p.amount_paise)}</td>
                <td className="px-3 py-2 text-xs">{p.method}</td>
                <td className="px-3 py-2 font-mono text-xs">{p.upi_reference ?? '—'}</td>
                <td className="px-3 py-2 text-xs">{p.status}</td>
                <td className="px-3 py-2 text-xs text-neutral-500">{new Date(p.created_at).toLocaleString()}</td>
                <td className="px-3 py-2 text-right">
                  {p.status === 'submitted' && (
                    <>
                      <button onClick={() => act(p.id, true)} className="btn-ghost text-green-700"><Check size={14} /></button>
                      <button onClick={() => act(p.id, false)} className="btn-ghost text-red-600"><X size={14} /></button>
                    </>
                  )}
                </td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr><td colSpan={8} className="px-3 py-6 text-center text-sm text-neutral-500">No payments.</td></tr>
            )}
          </tbody>
        </table>
      </div>
      <p className="mt-3 text-xs text-neutral-500">
        Always confirm the UPI reference against the merchant bank/UPI statement before approving. A screenshot alone is not proof.
      </p>
    </div>
  );
}
