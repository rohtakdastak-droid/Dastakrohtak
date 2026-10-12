import { useEffect, useState } from 'react';
import { Save } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { useCurrentVendor } from '../VendorLayout';

export default function VendorProfile() {
  const { vendor, setVendor } = useCurrentVendor();
  const [draft, setDraft] = useState(vendor);
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => { setDraft(vendor); }, [vendor]);

  async function save() {
    setBusy(true);
    setMsg(null);
    // Vendor members may update their own vendor record (RLS enforces).
    const { error } = await supabase
      .from('vendors')
      .update({
        description: draft.description,
        dispatch_address: draft.dispatch_address,
        latitude: draft.latitude,
        longitude: draft.longitude,
        prep_time_minutes: draft.prep_time_minutes,
        min_order_paise: draft.min_order_paise,
        service_radius_km: draft.service_radius_km,
      })
      .eq('id', vendor.id);
    setBusy(false);
    if (error) setMsg(error.message);
    else {
      setMsg('Saved.');
      setVendor(draft);
    }
  }

  return (
    <div>
      <h1 className="text-2xl font-bold">Profile</h1>
      <div className="text-sm text-neutral-500">Admins control name, category, images and account status.</div>

      <section className="card mt-4 p-5">
        <div className="grid grid-cols-2 gap-3">
          <F label="Name"><input className="input" value={draft.name} disabled /></F>
          <F label="Category"><input className="input capitalize" value={draft.category} disabled /></F>
          <F label="Description" className="col-span-2">
            <textarea className="input" rows={3} value={draft.description ?? ''} onChange={(e) => setDraft({ ...draft, description: e.target.value })} />
          </F>
          <F label="Dispatch address" className="col-span-2">
            <input className="input" value={draft.dispatch_address} onChange={(e) => setDraft({ ...draft, dispatch_address: e.target.value })} />
          </F>
          <F label="Latitude">
            <input className="input" type="number" step="0.000001" value={draft.latitude} onChange={(e) => setDraft({ ...draft, latitude: parseFloat(e.target.value) })} />
          </F>
          <F label="Longitude">
            <input className="input" type="number" step="0.000001" value={draft.longitude} onChange={(e) => setDraft({ ...draft, longitude: parseFloat(e.target.value) })} />
          </F>
          <F label="Prep time (minutes)">
            <input className="input" type="number" value={draft.prep_time_minutes} onChange={(e) => setDraft({ ...draft, prep_time_minutes: parseInt(e.target.value || '0', 10) })} />
          </F>
          <F label="Min order (paise)">
            <input className="input" type="number" value={draft.min_order_paise} onChange={(e) => setDraft({ ...draft, min_order_paise: parseInt(e.target.value || '0', 10) })} />
          </F>
          <F label="Service radius (km)">
            <input className="input" type="number" step="0.1" value={draft.service_radius_km} onChange={(e) => setDraft({ ...draft, service_radius_km: parseFloat(e.target.value) })} />
          </F>
        </div>
        <button className="btn-primary mt-4" disabled={busy} onClick={save}><Save size={14} /> Save</button>
        {msg && <div className="mt-2 text-xs text-neutral-500">{msg}</div>}
      </section>
    </div>
  );
}

function F({ label, className = '', children }: { label: string; className?: string; children: React.ReactNode }) {
  return (
    <label className={`block ${className}`}>
      <div className="mb-1 text-xs font-semibold text-neutral-500">{label}</div>
      {children}
    </label>
  );
}
