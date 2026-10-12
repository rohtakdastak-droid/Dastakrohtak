import { useEffect, useState } from 'react';
import { Save, QrCode, Shield } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { usePartner } from '../../lib/partner';

export default function PartnerProfile() {
  const { data, reload } = usePartner();
  const [vehicleType, setVehicleType] = useState('');
  const [vehicleNumber, setVehicleNumber] = useState('');
  const [docType, setDocType] = useState('driving_license');
  const [docRef, setDocRef] = useState('');
  const [docs, setDocs] = useState<any[]>([]);
  const [msg, setMsg] = useState<string | null>(null);

  useEffect(() => {
    if (data?.profile) {
      setVehicleType(data.profile.vehicle_type ?? '');
      setVehicleNumber(data.profile.vehicle_number ?? '');
    }
  }, [data?.profile]);

  async function loadDocs() {
    const { data: d } = await supabase.from('partner_documents').select('*').order('created_at', { ascending: false });
    setDocs(d ?? []);
  }
  useEffect(() => { loadDocs(); }, []);

  async function save() {
    setMsg(null);
    // upsert into delivery_partner_profiles — row exists if admin assigned the role.
    const { error } = await supabase
      .from('delivery_partner_profiles')
      .upsert({
        user_id: (await supabase.auth.getUser()).data.user!.id,
        vehicle_type: vehicleType || null,
        vehicle_number: vehicleNumber || null,
      }, { onConflict: 'user_id' });
    if (error) { setMsg(error.message); return; }
    setMsg('Saved.');
    reload();
  }

  async function addDoc() {
    if (!docRef) return;
    setMsg(null);
    // We store only a masked reference (never the raw ID). The actual file would go into
    // a private Supabase Storage bucket and the path saved here.
    const masked = docRef.length > 4 ? '••••' + docRef.slice(-4) : docRef;
    const { error } = await supabase.from('partner_documents').insert({
      partner_id: (await supabase.auth.getUser()).data.user!.id,
      doc_type: docType,
      file_path: `partner-docs/pending/${Date.now()}`,
      masked_reference: masked,
    });
    if (error) { setMsg(error.message); return; }
    setDocRef('');
    setMsg('Document submitted for review.');
    loadDocs();
  }

  if (!data) return <div className="p-6 text-sm text-neutral-500">Loading…</div>;

  return (
    <div>
      <h1 className="text-xl font-bold">Partner profile</h1>
      <div className="mt-1 text-xs text-neutral-500">
        Status: <span className="capitalize">{data.status}</span>
        {data.profile?.approved_at && ` · approved ${new Date(data.profile.approved_at).toLocaleDateString()}`}
      </div>

      <section className="card mt-4 p-4">
        <div className="flex items-center gap-2 text-sm font-semibold"><QrCode size={14} /> Partner QR</div>
        <div className="mt-1 text-xs text-neutral-500">
          Share this code with Dastak staff for verification. It does <b>not</b> contain any identity document.
        </div>
        <div className="mt-3 rounded-xl bg-neutral-50 p-4 text-center font-mono text-lg dark:bg-neutral-900">
          {data.profile?.partner_qr_code ?? '—'}
        </div>
      </section>

      <section className="card mt-4 p-4">
        <div className="text-sm font-semibold">Vehicle</div>
        <div className="mt-2 grid grid-cols-2 gap-3">
          <F label="Type">
            <select className="input" value={vehicleType} onChange={(e) => setVehicleType(e.target.value)}>
              <option value="">—</option>
              <option value="bike">Bike</option>
              <option value="scooter">Scooter</option>
              <option value="cycle">Cycle</option>
              <option value="car">Car</option>
            </select>
          </F>
          <F label="Vehicle number">
            <input className="input" value={vehicleNumber} onChange={(e) => setVehicleNumber(e.target.value)} placeholder="RJ14 AB 1234" />
          </F>
        </div>
        <button className="btn-primary mt-3 w-full sm:w-auto" onClick={save}><Save size={14} /> Save</button>
      </section>

      <section className="card mt-4 p-4">
        <div className="flex items-center gap-2 text-sm font-semibold"><Shield size={14} /> Verification documents</div>
        <p className="mt-1 text-xs text-neutral-500">
          Submit a document reference for admin review. Never share your full Aadhaar — Dastak only stores a masked reference and the admin verifies through an authorized process.
        </p>
        <div className="mt-3 grid grid-cols-2 gap-2">
          <select className="input" value={docType} onChange={(e) => setDocType(e.target.value)}>
            <option value="driving_license">Driving licence</option>
            <option value="vehicle_rc">Vehicle RC</option>
            <option value="id_proof">Masked ID proof</option>
          </select>
          <input className="input" placeholder="Reference number" value={docRef} onChange={(e) => setDocRef(e.target.value)} />
        </div>
        <button className="btn-outline mt-3" onClick={addDoc}>Submit for review</button>

        <div className="mt-4 divide-y divide-neutral-200 dark:divide-neutral-800">
          {docs.length === 0 && <div className="py-3 text-xs text-neutral-500">No documents submitted.</div>}
          {docs.map((d) => (
            <div key={d.id} className="flex items-center justify-between py-2 text-sm">
              <div>
                <div className="font-medium capitalize">{d.doc_type.replaceAll('_', ' ')}</div>
                <div className="text-xs text-neutral-500">Ref: {d.masked_reference}</div>
              </div>
              <div className="chip capitalize">{d.status}</div>
            </div>
          ))}
        </div>
      </section>

      {msg && <div className="mt-3 rounded-xl bg-neutral-100 p-3 text-sm dark:bg-neutral-900">{msg}</div>}
    </div>
  );
}

function F({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <div className="mb-1 text-xs font-semibold text-neutral-500">{label}</div>
      {children}
    </label>
  );
}
