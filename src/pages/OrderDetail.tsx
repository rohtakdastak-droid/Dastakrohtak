import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { ArrowLeft, QrCode } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { formatRupees } from '../lib/deliveryFee';

type OrderFull = any; // keep lean for scaffold

export default function OrderDetail() {
  const { id } = useParams();
  const [order, setOrder] = useState<OrderFull | null>(null);
  const [items, setItems] = useState<any[]>([]);
  const [paySettings, setPaySettings] = useState<any>(null);
  const [upiRef, setUpiRef] = useState('');
  const [msg, setMsg] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function reload() {
    const [{ data: o }, { data: it }, { data: s }] = await Promise.all([
      supabase.from('orders').select('*,vendors(name,dispatch_address)').eq('id', id).single(),
      supabase.from('order_items').select('*').eq('order_id', id),
      supabase.from('payment_settings').select('*').eq('id', true).single(),
    ]);
    setOrder(o);
    setItems(it ?? []);
    setPaySettings(s);
  }

  useEffect(() => {
    reload();
    // realtime
    const ch = supabase
      .channel(`order:${id}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'orders', filter: `id=eq.${id}` }, reload)
      .subscribe();
    return () => void supabase.removeChannel(ch);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  if (!order) return <div className="p-6 text-sm text-neutral-500">Loading…</div>;

  async function submitPayment() {
    setMsg(null);
    setSubmitting(true);
    const { error } = await supabase.rpc('submit_payment_proof', {
      p_order_id: order.id,
      p_upi_reference: upiRef,
      p_proof_image_path: null,
    });
    setSubmitting(false);
    if (error) setMsg(error.message);
    else {
      setMsg('Payment submitted. Awaiting verification.');
      reload();
    }
  }

  const needsPayment = ['pending_payment', 'payment_review'].includes(order.status) && order.payment_status !== 'verified';
  const upi = paySettings?.upi_vpa ?? (import.meta.env.VITE_FALLBACK_UPI_VPA as string | undefined);
  const payeeName = paySettings?.payee_name ?? (import.meta.env.VITE_FALLBACK_UPI_NAME as string | undefined) ?? 'Dastak';
  const amountRupees = (order.total_payable_paise / 100).toFixed(2);
  const upiHref = upi
    ? `upi://pay?pa=${encodeURIComponent(upi)}&pn=${encodeURIComponent(payeeName)}&am=${amountRupees}&cu=INR&tn=${encodeURIComponent(order.order_number)}`
    : null;

  return (
    <div className="p-4 pb-24">
      <Link to="/orders" className="inline-flex items-center gap-1 text-sm text-neutral-500"><ArrowLeft size={14} /> Orders</Link>
      <h1 className="mt-2 text-xl font-bold">Order {order.order_number}</h1>
      <div className="text-sm text-neutral-500">from {order.vendors?.name}</div>

      <div className="card mt-3 p-3">
        <div className="flex items-center justify-between text-sm">
          <span>Status</span>
          <span className="chip">{String(order.status).replaceAll('_', ' ')}</span>
        </div>
        <div className="mt-2 flex items-center justify-between text-sm">
          <span>Payment</span>
          <span className="chip">{order.payment_status}</span>
        </div>
      </div>

      <div className="card mt-3 p-3">
        <div className="text-sm font-semibold">Items</div>
        {items.map((i) => (
          <div key={i.id} className="mt-1 flex justify-between text-sm">
            <span>{i.quantity} × {i.product_name}</span>
            <span>{formatRupees(i.line_total_paise)}</span>
          </div>
        ))}
        <div className="mt-2 border-t border-neutral-200 pt-2 dark:border-neutral-800" />
        <Row k="Items subtotal" v={formatRupees(order.items_subtotal_paise)} />
        <Row k={`Delivery (${Number(order.delivery_distance_km).toFixed(2)} km)`} v={formatRupees(order.delivery_fee_paise)} />
        <Row k={<b>Total</b>} v={<b>{formatRupees(order.total_payable_paise)}</b>} />
      </div>

      {needsPayment && (
        <div className="card mt-3 p-4">
          <div className="flex items-center gap-2 text-sm font-semibold"><QrCode size={16} /> Pay via UPI</div>
          <div className="mt-2 text-xs text-neutral-500">
            Pay exactly {formatRupees(order.total_payable_paise)} to <b>{payeeName}</b>
            {upi && <> on <code>{upi}</code></>} and enter your UPI reference below.
          </div>
          {upiHref && (
            <a href={upiHref} className="btn-outline mt-3 w-full">Open UPI app</a>
          )}
          {paySettings?.qr_image_path && (
            <div className="mt-3 overflow-hidden rounded-xl bg-white p-3">
              {/* Private storage image loading would need a signed URL in a real build */}
              <div className="text-xs text-neutral-500">QR image: {paySettings.qr_image_path}</div>
            </div>
          )}
          <input className="input mt-3" placeholder="UPI transaction reference / UTR" value={upiRef} onChange={(e) => setUpiRef(e.target.value)} />
          <button className="btn-primary mt-2 w-full" disabled={!upiRef || submitting} onClick={submitPayment}>
            {submitting ? 'Submitting…' : 'I have paid — submit for verification'}
          </button>
          {msg && <div className="mt-2 text-xs text-neutral-500">{msg}</div>}
          <div className="mt-2 text-[11px] text-neutral-400">
            A screenshot or “I paid” click does not confirm payment. An admin verifies against the merchant account.
          </div>
        </div>
      )}
    </div>
  );
}

function Row({ k, v }: { k: React.ReactNode; v: React.ReactNode }) {
  return (
    <div className="mt-1 flex justify-between text-sm">
      <span className="text-neutral-500">{k}</span>
      <span>{v}</span>
    </div>
  );
}
