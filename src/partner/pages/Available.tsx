import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { MapPin, Clock, Bike, Zap } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatRupees } from '../../lib/deliveryFee';
import { usePartner } from '../../lib/partner';

type Row = {
  id: string; order_number: string; vendor_id: string; vendor_name: string;
  pickup_address: string; destination_address: string;
  delivery_distance_km: number; delivery_fee_paise: number;
  items_subtotal_paise: number; total_payable_paise: number;
  created_at: string;
  pickup_lat: number; pickup_lng: number;
  destination_lat: number; destination_lng: number;
};

export default function Available() {
  const { data, reload } = usePartner();
  const [rows, setRows] = useState<Row[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const nav = useNavigate();

  async function load() {
    const { data: r, error } = await supabase.rpc('list_available_orders');
    if (error) {
      // Not approved yet, or no orders — show empty gracefully.
      setRows([]);
      return;
    }
    setRows((r as Row[]) ?? []);
  }

  useEffect(() => {
    if (data?.status === 'active') load();
    const ch = supabase
      .channel('partner:available')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'orders' }, () => {
        if (data?.status === 'active') load();
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'delivery_assignments' }, () => {
        if (data?.status === 'active') load();
      })
      .subscribe();
    return () => void supabase.removeChannel(ch);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data?.status]);

  async function toggleOnline() {
    if (!data?.profile) return;
    const next = !data.profile.is_online;
    await supabase.rpc('set_partner_online', { p_online: next });
    reload();
  }

  async function accept(orderId: string) {
    setErr(null);
    setBusy(orderId);
    const { data: assignmentId, error } = await supabase.rpc('accept_delivery', { p_order_id: orderId });
    setBusy(null);
    if (error) {
      setErr(error.message);
      load();
      return;
    }
    nav('/partner/active');
    void assignmentId;
  }

  const notApproved = data?.status !== 'active' || !data.profile?.approved_at;

  return (
    <div>
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-bold">Available orders</h1>
        {!notApproved && (
          <button
            onClick={toggleOnline}
            className={`inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-xs font-semibold ${
              data?.profile?.is_online
                ? 'border-green-600 bg-green-50 text-green-700 dark:bg-green-600/10'
                : 'border-neutral-200 dark:border-neutral-800'
            }`}
          >
            <span className={`h-2 w-2 rounded-full ${data?.profile?.is_online ? 'bg-green-500' : 'bg-neutral-400'}`} />
            {data?.profile?.is_online ? 'Online' : 'Offline'}
          </button>
        )}
      </div>

      {notApproved && (
        <div className="card mt-4 p-4 text-sm text-neutral-500">
          You can accept orders once your profile is approved by admin.
        </div>
      )}

      {err && <div className="mt-3 rounded-xl bg-red-50 p-3 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200">{err}</div>}

      <div className="mt-4 space-y-3">
        {!notApproved && rows.length === 0 && (
          <div className="card p-6 text-center text-sm text-neutral-500">
            No orders available right now. New orders will appear here live.
          </div>
        )}

        {rows.map((o) => (
          <div key={o.id} className="card p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="font-mono text-xs text-neutral-500">#{o.order_number}</div>
                <div className="mt-0.5 font-semibold">{o.vendor_name}</div>
              </div>
              <div className="text-right">
                <div className="text-xs text-neutral-500">Earning</div>
                <div className="text-lg font-bold text-brand-600">{formatRupees(o.delivery_fee_paise)}</div>
              </div>
            </div>

            <div className="mt-3 space-y-1 text-xs">
              <div className="flex items-start gap-2">
                <MapPin size={14} className="mt-0.5 shrink-0 text-emerald-600" />
                <div><b>Pickup:</b> {o.pickup_address}</div>
              </div>
              <div className="flex items-start gap-2">
                <MapPin size={14} className="mt-0.5 shrink-0 text-rose-600" />
                <div><b>Drop:</b> {o.destination_address}</div>
              </div>
            </div>

            <div className="mt-3 flex items-center gap-3 text-xs text-neutral-500">
              <span className="inline-flex items-center gap-1"><Bike size={12} /> {Number(o.delivery_distance_km).toFixed(2)} km</span>
              <span className="inline-flex items-center gap-1"><Clock size={12} /> {new Date(o.created_at).toLocaleTimeString()}</span>
            </div>

            <button
              className="btn-primary mt-3 w-full"
              disabled={busy === o.id || notApproved}
              onClick={() => accept(o.id)}
            >
              <Zap size={16} /> {busy === o.id ? 'Accepting…' : 'Accept delivery'}
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
