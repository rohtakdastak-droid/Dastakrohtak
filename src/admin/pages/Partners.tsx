import { useEffect, useState } from 'react';
import { Check, Pause, Play, UserPlus, Copy } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { adminCreateUser } from '../../lib/adminApi';

type Row = {
  user_id: string;
  partner_qr_code: string | null;
  vehicle_number: string | null;
  approved_at: string | null;
  is_online: boolean;
  profile: { display_name: string | null; phone: string | null; status: string } | null;
};

export default function Partners() {
  const [rows, setRows] = useState<Row[]>([]);
  const [email, setEmail] = useState('');
  const [msg, setMsg] = useState<string | null>(null);

  // New partner creation
  const [showCreate, setShowCreate] = useState(false);
  const [newEmail, setNewEmail] = useState('');
  const [newName, setNewName] = useState('');
  const [newPhone, setNewPhone] = useState('');
  const [creating, setCreating] = useState(false);
  const [createResult, setCreateResult] = useState<{ email: string; password: string } | null>(null);
  const [createError, setCreateError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  async function load() {
    const { data } = await supabase
      .from('delivery_partner_profiles')
      .select('user_id,partner_qr_code,vehicle_number,approved_at,is_online,profile:profiles!user_id(display_name,phone,status)')
      .order('user_id');
    setRows((data as unknown as Row[]) ?? []);
  }
  useEffect(() => { load(); }, []);

  async function assignByEmail() {
    setMsg(null);
    const { data: prof, error } = await supabase.from('profiles')
      .select('id, display_name').ilike('display_name', email).limit(1);
    if (error) { setMsg(error.message); return; }
    if (!prof || prof.length === 0) {
      setMsg('No user found with that display name. Use "Create new partner" instead.');
      return;
    }
    const { error: e2 } = await supabase.rpc('admin_assign_delivery_role', { p_user_id: prof[0].id });
    if (e2) setMsg(e2.message);
    else { setMsg('Assigned.'); load(); }
  }

  async function createPartner() {
    if (!newEmail) return;
    setCreating(true);
    setCreateError(null);
    const res = await adminCreateUser({
      email: newEmail,
      display_name: newName || undefined,
      phone: newPhone || undefined,
      role: 'delivery',
    });
    setCreating(false);
    if (res.ok) {
      setCreateResult({ email: res.email, password: res.password });
      load();
    } else {
      setCreateError(res.message || res.error);
    }
  }

  function copyCredentials() {
    if (!createResult) return;
    navigator.clipboard.writeText(`Email: ${createResult.email}\nPassword: ${createResult.password}`);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  function closeCreateDialog() {
    setShowCreate(false);
    setNewEmail('');
    setNewName('');
    setNewPhone('');
    setCreateResult(null);
    setCreateError(null);
  }

  async function setStatus(uid: string, s: 'active' | 'suspended' | 'rejected') {
    const { error } = await supabase.rpc('admin_set_partner_status', { p_user_id: uid, p_status: s });
    if (error) alert(error.message);
    load();
  }

  return (
    <div>
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Delivery partners</h1>
        <button className="btn-primary" onClick={() => setShowCreate(true)}>
          <UserPlus size={16} /> Create new partner
        </button>
      </div>

      <div className="card mt-4 p-4">
        <div className="text-sm font-semibold">Assign existing user</div>
        <div className="mt-1 text-xs text-neutral-500">
          If someone already has an account, enter their display name to give them the delivery role.
        </div>
        <div className="mt-3 flex gap-2">
          <input className="input" placeholder="User display name" value={email} onChange={(e) => setEmail(e.target.value)} />
          <button className="btn-outline" onClick={assignByEmail}><UserPlus size={14} /> Assign</button>
        </div>
        {msg && <div className="mt-2 text-xs text-neutral-500">{msg}</div>}
      </div>

      <div className="mt-4 overflow-x-auto rounded-2xl border border-neutral-200 dark:border-neutral-800">
        <table className="w-full text-left text-sm">
          <thead className="bg-neutral-50 text-xs uppercase text-neutral-500 dark:bg-neutral-900">
            <tr>
              <th className="px-3 py-2">Partner</th>
              <th className="px-3 py-2">Phone</th>
              <th className="px-3 py-2">Vehicle</th>
              <th className="px-3 py-2">QR</th>
              <th className="px-3 py-2">Status</th>
              <th className="px-3 py-2">Approved</th>
              <th className="px-3 py-2">Online</th>
              <th className="px-3 py-2 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-neutral-100 dark:divide-neutral-900">
            {rows.map((r) => (
              <tr key={r.user_id}>
                <td className="px-3 py-2 font-medium">{r.profile?.display_name ?? r.user_id.slice(0, 8)}</td>
                <td className="px-3 py-2 text-xs">{r.profile?.phone ?? '—'}</td>
                <td className="px-3 py-2 text-xs">{r.vehicle_number ?? '—'}</td>
                <td className="px-3 py-2 font-mono text-xs">{r.partner_qr_code}</td>
                <td className="px-3 py-2 text-xs">{r.profile?.status ?? '—'}</td>
                <td className="px-3 py-2 text-xs text-neutral-500">{r.approved_at ? new Date(r.approved_at).toLocaleDateString() : '—'}</td>
                <td className="px-3 py-2">
                  <span className={`h-2 w-2 inline-block rounded-full ${r.is_online ? 'bg-green-500' : 'bg-neutral-300'}`} />
                </td>
                <td className="px-3 py-2 text-right">
                  {r.profile?.status === 'pending' && (
                    <button className="btn-ghost text-green-700" onClick={() => setStatus(r.user_id, 'active')}><Check size={14} /> Approve</button>
                  )}
                  {r.profile?.status === 'active' && (
                    <button className="btn-ghost text-amber-700" onClick={() => setStatus(r.user_id, 'suspended')}><Pause size={14} /> Suspend</button>
                  )}
                  {r.profile?.status === 'suspended' && (
                    <button className="btn-ghost text-green-700" onClick={() => setStatus(r.user_id, 'active')}><Play size={14} /> Reactivate</button>
                  )}
                </td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr><td colSpan={8} className="px-3 py-6 text-center text-sm text-neutral-500">No delivery partners yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>

      {showCreate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="card w-full max-w-md p-5">
            <div className="text-lg font-semibold">Create delivery partner</div>

            {!createResult ? (
              <>
                <div className="mt-3 space-y-3">
                  <label className="block">
                    <div className="mb-1 text-xs font-semibold text-neutral-500">Email *</div>
                    <input className="input" type="email" placeholder="partner@example.com" value={newEmail} onChange={(e) => setNewEmail(e.target.value)} />
                  </label>
                  <label className="block">
                    <div className="mb-1 text-xs font-semibold text-neutral-500">Name</div>
                    <input className="input" placeholder="Full name" value={newName} onChange={(e) => setNewName(e.target.value)} />
                  </label>
                  <label className="block">
                    <div className="mb-1 text-xs font-semibold text-neutral-500">Phone</div>
                    <input className="input" placeholder="+91..." value={newPhone} onChange={(e) => setNewPhone(e.target.value)} />
                  </label>
                </div>
                {createError && <div className="mt-3 rounded-xl bg-red-50 p-3 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200">{createError}</div>}
                <div className="mt-5 flex justify-end gap-2">
                  <button className="btn-outline" onClick={closeCreateDialog}>Cancel</button>
                  <button className="btn-primary" disabled={!newEmail || creating} onClick={createPartner}>
                    {creating ? 'Creating…' : 'Create account'}
                  </button>
                </div>
              </>
            ) : (
              <>
                <div className="mt-4 rounded-xl border border-green-200 bg-green-50 p-4 dark:border-green-800 dark:bg-green-900/20">
                  <div className="text-sm font-semibold text-green-800 dark:text-green-200">Account created & approved!</div>
                  <div className="mt-2 space-y-1 font-mono text-sm">
                    <div><span className="text-neutral-500">Email:</span> {createResult.email}</div>
                    <div><span className="text-neutral-500">Password:</span> {createResult.password}</div>
                  </div>
                  <button onClick={copyCredentials} className="btn-outline mt-3 inline-flex items-center gap-1 text-xs">
                    {copied ? <><Check size={12} /> Copied!</> : <><Copy size={12} /> Copy credentials</>}
                  </button>
                </div>
                <p className="mt-3 text-xs text-neutral-500">Share these with the delivery partner. They can change the password after first login.</p>
                <div className="mt-4 flex justify-end">
                  <button className="btn-primary" onClick={closeCreateDialog}>Done</button>
                </div>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
