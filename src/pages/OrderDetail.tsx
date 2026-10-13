import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { ArrowLeft, QrCode, Truck, Clock, Copy, Check, ExternalLink, MapPin, Receipt, CheckCircle2, Circle } from 'lucide-react';
import { Capacitor } from '@capacitor/core';
import Upi from '../lib/upiPlugin';
import { supabase } from '../lib/supabase';
import { formatRupees } from '../lib/deliveryFee';

type OrderFull = any;

const STATUS_META: Record<string, { label: string; color: string }> = {
  pending_payment: { label: 'Payment pending', color: 'bg-amber-100 text-amber-800 dark:bg-amber-500/15 dark:text-amber-200' },
  payment_review: { label: 'Payment under review', color: 'bg-amber-100 text-amber-800 dark:bg-amber-500/15 dark:text-amber-200' },
  payment_verified: { label: 'Payment verified', color: 'bg-sky-100 text-sky-800 dark:bg-sky-500/15 dark:text-sky-200' },
  vendor_confirmation: { label: 'Restaurant confirming', color: 'bg-indigo-100 text-indigo-800 dark:bg-indigo-500/15 dark:text-indigo-200' },
  preparing: { label: 'Preparing your food', color: 'bg-orange-100 text-orange-800 dark:bg-orange-500/15 dark:text-orange-200' },
  ready_for_pickup: { label: 'Ready for pickup', color: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-500/15 dark:text-emerald-200' },
  assigned: { label: 'Partner assigned', color: 'bg-sky-100 text-sky-800 dark:bg-sky-500/15 dark:text-sky-200' },
  picked_up: { label: 'Picked up', color: 'bg-sky-100 text-sky-800 dark:bg-sky-500/15 dark:text-sky-200' },
  out_for_delivery: { label: 'Out for delivery', color: 'bg-sky-100 text-sky-800 dark:bg-sky-500/15 dark:text-sky-200' },
  delivered: { label: 'Delivered', color: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-500/15 dark:text-emerald-200' },
  rejected: { label: 'Rejected by restaurant', color: 'bg-red-100 text-red-800 dark:bg-red-500/15 dark:text-red-200' },
  cancelled: { label: 'Cancelled', color: 'bg-neutral-200 text-neutral-700 dark:bg-neutral-700 dark:text-neutral-200' },
};

const PROGRESS_STEPS = [
  { key: 'payment_verified', label: 'Payment confirmed' },
  { key: 'vendor_confirmation', label: 'Order placed' },
  { key: 'preparing', label: 'Preparing' },
  { key: 'ready_for_pickup', label: 'Ready' },
  { key: 'out_for_delivery', label: 'On the way' },
  { key: 'delivered', label: 'Delivered' },
];

const PROGRESS_INDEX: Record<string, number> = {
  pending_payment: 0,
  payment_review: 0,
  payment_verified: 1,
  vendor_confirmation: 1,
  preparing: 2,
  ready_for_pickup: 3,
  assigned: 4,
  picked_up: 4,
  out_for_delivery: 4,
  delivered: 5,
};

function statusPill(status: string) {
  const m = STATUS_META[status] ?? { label: status.replaceAll('_', ' '), color: 'bg-neutral-100 text-neutral-700 dark:bg-neutral-800 dark:text-neutral-200' };
  return <span className={`inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold ${m.color}`}>{m.label}</span>;
}

export default function OrderDetail() {
  const { id } = useParams();
  const [order, setOrder] = useState<OrderFull | null>(null);
  const [items, setItems] = useState<any[]>([]);
  const [paySettings, setPaySettings] = useState<any>(null);
  const [upiRef, setUpiRef] = useState('');
  const [msg, setMsg] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [loadError, setLoadError] = useState(false);
  const [qrUrl, setQrUrl] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  async function reload() {
    const [{ data: o, error: oErr }, { data: it }, { data: s }] = await Promise.all([
      supabase.from('orders').select('*,vendors(name,dispatch_address)').eq('id', id).single(),
      supabase.from('order_items').select('*').eq('order_id', id),
      supabase.from('payment_settings').select('*').eq('id', true).single(),
    ]);
    if (oErr || !o) { setLoadError(true); return; }
    setOrder(o);
    setItems(it ?? []);
    setPaySettings(s);
  }

  useEffect(() => {
    let retries = 0;
    let loaded = false;
    async function tryLoad() {
      const { data: o } = await supabase.from('orders').select('*,vendors(name,dispatch_address)').eq('id', id).single();
      if (o) { loaded = true; setOrder(o); }
      const [{ data: it }, { data: s }] = await Promise.all([
        supabase.from('order_items').select('*').eq('order_id', id),
        supabase.from('payment_settings').select('*').eq('id', true).single(),
      ]);
      setItems(it ?? []);
      setPaySettings(s);
      if (s?.qr_image_path) {
        const { data: u } = supabase.storage.from('payment-qr').getPublicUrl(s.qr_image_path);
        if (u?.publicUrl) setQrUrl(u.publicUrl);
      }
      if (!loaded && retries < 3) {
        retries++;
        setTimeout(tryLoad, 1500);
      } else if (!loaded) {
        setLoadError(true);
      }
    }
    tryLoad();
    const ch = supabase
      .channel(`order:${id}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'orders', filter: `id=eq.${id}` }, reload)
      .subscribe();
    return () => void supabase.removeChannel(ch);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  if (loadError) return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center p-6 text-center">
      <div className="text-4xl">😕</div>
      <div className="mt-3 text-sm font-medium">Could not load order</div>
      <div className="mt-1 text-xs text-neutral-500">Order ID: {id}</div>
      <button onClick={() => { setLoadError(false); reload(); }} className="btn-primary mt-4">Retry</button>
      <Link to="/orders" className="mt-2 text-sm text-brand-600">← Back to orders</Link>
    </div>
  );
  if (!order) return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center p-6">
      <div className="h-8 w-8 animate-spin rounded-full border-4 border-brand-200 border-t-brand-600" />
      <div className="mt-3 text-sm font-medium">Loading order…</div>
    </div>
  );

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
  const upi = paySettings?.upi_vpa || (import.meta.env.VITE_FALLBACK_UPI_VPA as string | undefined) || 'dastak@upi';
  const payeeName = paySettings?.payee_name || (import.meta.env.VITE_FALLBACK_UPI_NAME as string | undefined) || 'Dastak';
  const amountRupees = (order.total_payable_paise / 100).toFixed(2);
  const upiHref = upi
    ? `upi://pay?pa=${encodeURIComponent(upi)}&pn=${encodeURIComponent(payeeName)}&am=${amountRupees}&cu=INR&tn=${encodeURIComponent(order.order_number)}`
    : null;

  const progressIdx = PROGRESS_INDEX[order.status] ?? 0;
  const isTerminal = order.status === 'rejected' || order.status === 'cancelled';

  return (
    <div className="pb-24">
      {/* Hero header */}
      <div className="bg-gradient-to-br from-brand-500 via-brand-600 to-brand-700 px-4 pb-6 pt-5 text-white">
        <Link to="/orders" className="inline-flex items-center gap-1 text-xs font-medium text-white/80">
          <ArrowLeft size={14} /> Back to orders
        </Link>
        <div className="mt-3 flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="text-[11px] font-semibold uppercase tracking-widest text-white/60">Order</div>
            <h1 className="truncate text-2xl font-bold tracking-tight">#{order.order_number}</h1>
            <div className="mt-1 truncate text-sm text-white/80">from {order.vendors?.name}</div>
          </div>
          <div className="shrink-0 rounded-2xl bg-white/15 px-3 py-2 text-right backdrop-blur">
            <div className="text-[10px] font-semibold uppercase tracking-widest text-white/70">Total</div>
            <div className="text-lg font-bold">{formatRupees(order.total_payable_paise)}</div>
          </div>
        </div>
        <div className="mt-3">{statusPill(order.status)}</div>
      </div>

      <div className="px-4">
        {/* Progress tracker */}
        {!isTerminal && (
          <div className="card -mt-4 p-4 shadow-md">
            <div className="text-xs font-semibold text-neutral-500">Order progress</div>
            <div className="mt-3 space-y-3">
              {PROGRESS_STEPS.map((step, idx) => {
                const done = idx <= progressIdx;
                const active = idx === progressIdx;
                return (
                  <div key={step.key} className="flex items-center gap-3">
                    {done ? (
                      <CheckCircle2 size={18} className={active ? 'text-brand-500' : 'text-emerald-500'} />
                    ) : (
                      <Circle size={18} className="text-neutral-300 dark:text-neutral-700" />
                    )}
                    <div className={`text-sm ${done ? 'font-semibold text-neutral-800 dark:text-neutral-100' : 'text-neutral-400'}`}>
                      {step.label}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {isTerminal && (
          <div className="card -mt-4 p-4 shadow-md">
            <div className="text-sm font-semibold text-red-600">
              This order was {order.status === 'rejected' ? 'rejected by the restaurant' : 'cancelled'}.
            </div>
            {order.vendor_reject_reason && (
              <div className="mt-1 text-xs text-neutral-500">Reason: {order.vendor_reject_reason}</div>
            )}
          </div>
        )}

        {/* Items */}
        <div className="card mt-3 p-4">
          <div className="flex items-center gap-2 text-sm font-semibold">
            <Receipt size={16} className="text-brand-600" /> Items
          </div>
          <div className="mt-3 space-y-2">
            {items.map((i) => (
              <div key={i.id} className="flex justify-between text-sm">
                <span><span className="font-semibold text-brand-600">{i.quantity}×</span> {i.product_name}</span>
                <span className="font-medium">{formatRupees(i.line_total_paise)}</span>
              </div>
            ))}
          </div>
          <div className="mt-3 border-t border-neutral-100 pt-3 dark:border-neutral-800">
            <Row k="Items subtotal" v={formatRupees(order.items_subtotal_paise)} />
            <Row k={`Delivery (${Number(order.delivery_distance_km).toFixed(2)} km)`} v={formatRupees(order.delivery_fee_paise)} />
            <div className="mt-2 flex justify-between border-t border-neutral-100 pt-2 text-sm font-bold dark:border-neutral-800">
              <span>Total</span>
              <span className="text-brand-600">{formatRupees(order.total_payable_paise)}</span>
            </div>
          </div>
        </div>

        {/* Delivery address */}
        <div className="card mt-3 p-4">
          <div className="flex items-center gap-2 text-sm font-semibold">
            <MapPin size={16} className="text-brand-600" /> Delivering to
          </div>
          <div className="mt-2 text-sm text-neutral-700 dark:text-neutral-300">{order.destination_address}</div>
        </div>

        {needsPayment && (
          <>
            {/* QR Code Payment */}
            <div className="card mt-3 p-4">
              <div className="flex items-center gap-2 text-sm font-semibold"><QrCode size={16} className="text-brand-600" /> Scan QR & pay</div>
              <div className="mt-2 text-xs text-neutral-500">
                Pay exactly <b>{formatRupees(order.total_payable_paise)}</b> by scanning the QR code below
                {payeeName && <> to <b>{payeeName}</b></>}.
              </div>

              {qrUrl && (
                <div className="mx-auto mt-3 w-56 overflow-hidden rounded-2xl border border-neutral-200 bg-white p-3 dark:border-neutral-700">
                  <img src={qrUrl} alt="Payment QR Code" className="h-auto w-full" />
                </div>
              )}

              {upi && (
                <div className="mt-3 flex items-center justify-between rounded-xl bg-neutral-100 px-3 py-2.5 dark:bg-neutral-800">
                  <div className="text-xs text-neutral-600 dark:text-neutral-400">
                    UPI ID: <b className="select-all">{upi}</b>
                  </div>
                  <button
                    className="ml-2 flex items-center gap-1 rounded-lg bg-white px-2 py-1 text-[11px] font-semibold text-brand-600 shadow-sm transition active:scale-95 dark:bg-neutral-700 dark:text-brand-400"
                    onClick={() => {
                      navigator.clipboard.writeText(upi).then(() => {
                        setCopied(true);
                        setTimeout(() => setCopied(false), 2000);
                      });
                    }}
                  >
                    {copied ? <><Check size={12} /> Copied</> : <><Copy size={12} /> Copy</>}
                  </button>
                </div>
              )}

              {upiHref && (
                <button
                  className="btn-primary mt-3 w-full"
                  onClick={async () => {
                    if (Capacitor.isNativePlatform()) {
                      try {
                        await Upi.pay({ uri: upiHref });
                      } catch {
                        window.location.href = upiHref;
                      }
                    } else {
                      window.location.href = upiHref;
                    }
                  }}
                ><ExternalLink size={14} /> Open UPI app to pay</button>
              )}

              <div className="mt-4 border-t border-neutral-200 pt-3 dark:border-neutral-800">
                <div className="text-xs font-medium text-neutral-600 dark:text-neutral-400">After payment, enter your UTR / reference number:</div>
                <input className="input mt-2" placeholder="UPI transaction reference / UTR" value={upiRef} onChange={(e) => setUpiRef(e.target.value)} />
                <button className="btn-primary mt-2 w-full" disabled={!upiRef || submitting} onClick={submitPayment}>
                  {submitting ? 'Submitting…' : 'Submit payment proof'}
                </button>
              </div>
              {msg && <div className="mt-2 text-xs text-emerald-600">{msg}</div>}
              <div className="mt-2 text-[11px] text-neutral-400">
                Admin will verify your payment against the merchant account.
              </div>
            </div>

            {/* COD - Coming Soon */}
            <div className="card mt-3 p-4 opacity-60">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2 text-sm font-semibold"><Truck size={16} /> Cash on delivery</div>
                <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2.5 py-0.5 text-[11px] font-semibold text-amber-700 dark:bg-amber-500/10 dark:text-amber-400">
                  <Clock size={10} /> Coming soon
                </span>
              </div>
              <div className="mt-1 text-xs text-neutral-500">Pay with cash when your order is delivered.</div>
            </div>
          </>
        )}
      </div>
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
