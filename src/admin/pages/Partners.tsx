import { useEffect, useState } from 'react';
import { Check, Pause, Play, UserPlus, Copy, Package, Wallet, Store } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { adminCreateUser } from '../../lib/adminApi';
import { formatRupees } from '../../lib/deliveryFee';

type Row = {
  user_id: string;
  partner_qr_code: string | null;
  vehicle_number: string | null;
  approved_at: string | null;
  is_online: boolean;
  profile: { display_name: string | null; phone: string | null; status: string } | null;
};

type PartnerStats = {
  deliveries: number;
  earnings: number;
  restaurants: { name: string; count: number }[];
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

  const [pStats, setPStats] = useState<Record<string, PartnerStats>>({});
  const [expanded, setExpanded] = useState<string | null>(null);

  async function load() {
    const { data } = await supabase
      .from('delivery_partner_profiles')
      .select('user_id,partner_qr_code,vehicle_number,approved_at,is_online,profile:profiles!user_id(display_name,phone,status)')
      .order('user_id');
    const partners = (data as unknown as Row[]) ?? [];
    setRows(partners);

    const stats: Record<string, PartnerStats> = {};
    await Promise.all(partners.map(async (p) => {
      const [delCount, earnData, vendorData] = await Promise.all([
        supabase.from('delivery_assignments').select('id', { count: 'exact', head: true }).eq('partner_id', p.user_id).eq('status', 'accepted'),
        supabase.from('delivery_earnings').select('net_paise').eq('partner_id', p.user_id),
        supabase.from('delivery_assignments').select('orders!inner(vendor_id, vendors(name))').eq('partner_id', p.user_id).eq('status', 'accepted'),
      ]);
      const rMap = new Map<string, { name: string; count: number }>();
      for (const a of (vendorData.data ?? []) as any[]) {
        const vid = a.orders?.vendor_id;
        const vname = a.orders?.vendors?.name ?? 'Unknown';
        if (!vid) continue;
        const cur = rMap.get(vid);
        if (cur) cur.count++;
        else rMap.set(vid, { name: vname, count: 1 });
      }
      stats[p.user_id] = {
        deliveries: delCount.count ?? 0,
        earnings: (earnData.data ?? []).reduce((s: number, r: any) => s + r.net_paise, 0),
        restaurants: Array.from(rMap.values()).sort((a, b) => b.count - a.count),
      };
    }));
    setPStats(stats);
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
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-xl font-bold md:text-2xl">Delivery partners</h1>
        <button className="btn-primary shrink-0 text-xs md:text-sm" onClick={() => setShowCreate(true)}>
          <UserPlus size={16} /> <span className="hidden sm:inline">Create new partner</span><span className="sm:hidden">Create</span>
        </button>
      </div>

      <div className="card mt-4 p-3 md:p-4">
        <div className="text-sm font-semibold">Assign existing user</div>
        <div className="mt-1 text-xs text-neutral-500">
          If someone already has an account, enter their display name to give them the delivery role.
        </div>
        <div className="mt-3 flex flex-col gap-2 sm:flex-row">
          <input className="input flex-1" placeholder="User display name" value={email} onChange={(e) => setEmail(e.target.value)} />
          <button className="btn-outline shrink-0" onClick={assignByEmail}><UserPlus size={14} /> Assign</button>
        </div>
        {msg && <div className="mt-2 text-xs text-neutral-500">{msg}</div>}
      </div>

      {/* Mobile card layout */}
      <div className="mt-4 space-y-2 md:hidden">
        {rows.map((r) => {
          const st = pStats[r.user_id];
          return (
          <div key={r.user_id} className="card p-3">
            <div className="flex items-start justify-between gap-2" onClick={() => setExpanded(expanded === r.user_id ? null : r.user_id)}>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="font-semibold">{r.profile?.display_name ?? r.user_id.slice(0, 8)}</span>
                  <span className={`h-2 w-2 rounded-full ${r.is_online ? 'bg-green-500' : 'bg-neutral-300'}`} />
                </div>
                <div className="mt-1 text-xs text-neutral-500">{r.profile?.phone ?? 'No phone'}</div>
                {r.vehicle_number && <div className="text-xs text-neutral-400">Vehicle: {r.vehicle_number}</div>}
              </div>
              <div className="text-right shrink-0">
                <div className="text-xs font-medium capitalize">{r.profile?.status ?? '—'}</div>
                <div className="text-[10px] text-neutral-400">{r.approved_at ? new Date(r.approved_at).toLocaleDateString() : 'Not approved'}</div>
              </div>
            </div>
            {/* Stats row */}
            <div className="mt-2 flex items-center gap-3 text-[11px]">
              <span className="inline-flex items-center gap-1 text-neutral-500"><Package size={12} /> {st?.deliveries ?? 0} deliveries</span>
              <span className="inline-flex items-center gap-1 text-green-600"><Wallet size={12} /> {formatRupees(st?.earnings ?? 0)}</span>
              <span className="inline-flex items-center gap-1 text-neutral-400"><Store size={12} /> {st?.restaurants.length ?? 0} restaurants</span>
            </div>
            {/* Expanded detail */}
            {expanded === r.user_id && st && st.restaurants.length > 0 && (
              <div className="mt-2 rounded-lg bg-neutral-50 p-2 dark:bg-neutral-900">
                <div className="text-[10px] font-semibold uppercase tracking-wider text-neutral-500">Restaurants</div>
                {st.restaurants.map((rest) => (
                  <div key={rest.name} className="mt-1 flex items-center justify-between text-xs">
                    <span>{rest.name}</span>
                    <span className="text-neutral-500">{rest.count} deliveries</span>
                  </div>
                ))}
              </div>
            )}
            <div className="mt-2 flex items-center gap-2 border-t border-neutral-100 pt-2 dark:border-neutral-800">
              {r.partner_qr_code && <span className="truncate rounded bg-neutral-100 px-2 py-0.5 font-mono text-[10px] dark:bg-neutral-800">{r.partner_qr_code}</span>}
              <div className="flex-1" />
              {r.profile?.status === 'pending' && (
                <button className="flex items-center gap-1 rounded-lg bg-green-50 px-2.5 py-1 text-xs font-medium text-green-700 dark:bg-green-500/10" onClick={() => setStatus(r.user_id, 'active')}><Check size={12} /> Approve</button>
              )}
              {r.profile?.status === 'active' && (
                <button className="flex items-center gap-1 rounded-lg bg-amber-50 px-2.5 py-1 text-xs font-medium text-amber-700 dark:bg-amber-500/10" onClick={() => setStatus(r.user_id, 'suspended')}><Pause size={12} /> Suspend</button>
              )}
              {r.profile?.status === 'suspended' && (
                <button className="flex items-center gap-1 rounded-lg bg-green-50 px-2.5 py-1 text-xs font-medium text-green-700 dark:bg-green-500/10" onClick={() => setStatus(r.user_id, 'active')}><Play size={12} /> Reactivate</button>
              )}
            </div>
          </div>
          );
        })}
        {rows.length === 0 && <div className="py-6 text-center text-sm text-neutral-500">No delivery partners yet.</div>}
      </div>

      {/* Desktop table */}
      <div className="mt-4 hidden overflow-x-auto rounded-2xl border border-neutral-200 dark:border-neutral-800 md:block">
        <table className="w-full text-left text-sm">
          <thead className="bg-neutral-50 text-xs uppercase text-neutral-500 dark:bg-neutral-900">
            <tr>
              <th className="px-3 py-2">Partner</th>
              <th className="px-3 py-2">Phone</th>
              <th className="px-3 py-2">Vehicle</th>
              <th className="px-3 py-2">QR</th>
              <th className="px-3 py-2">Status</th>
              <th className="px-3 py-2 text-center">Deliveries</th>
              <th className="px-3 py-2 text-right">Earnings</th>
              <th className="px-3 py-2 text-center">Restaurants</th>
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
                <td className="px-3 py-2 text-center font-semibold">{pStats[r.user_id]?.deliveries ?? 0}</td>
                <td className="px-3 py-2 text-right font-semibold text-green-600">{formatRupees(pStats[r.user_id]?.earnings ?? 0)}</td>
                <td className="px-3 py-2 text-center text-xs">{pStats[r.user_id]?.restaurants.map(r => r.name).join(', ') || '—'}</td>
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
              <tr><td colSpan={11} className="px-3 py-6 text-center text-sm text-neutral-500">No delivery partners yet.</td></tr>
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
