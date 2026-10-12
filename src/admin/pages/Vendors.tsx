import { useEffect, useState } from 'react';
import { Plus, Pencil, Power, ArrowUp, ArrowDown, Trash2, Star, UserPlus, Copy, Check } from 'lucide-react';
import { supabase, type Vendor } from '../../lib/supabase';
import { adminCreateUser } from '../../lib/adminApi';

const CATS = ['food'] as const;

const EMPTY = {
  name: '', slug: '', category: 'food' as (typeof CATS)[number], description: '',
  dispatch_address: '', latitude: 26.9124, longitude: 75.7873,
  min_order_paise: 0, prep_time_minutes: 20, service_radius_km: 7.0,
  is_active: true, is_featured: false, sort_priority: 100,
};

export default function Vendors() {
  const [list, setList] = useState<Vendor[]>([]);
  const [editing, setEditing] = useState<Partial<Vendor> | null>(null);
  const [filter, setFilter] = useState<string>('all');

  async function load() {
    const { data } = await supabase.from('vendors').select('*').order('sort_priority');
    setList((data as Vendor[]) ?? []);
  }
  useEffect(() => { load(); }, []);

  async function save() {
    if (!editing) return;
    if (editing.id) {
      const { id, ...patch } = editing as Vendor;
      await supabase.from('vendors').update(patch).eq('id', id);
    } else {
      await supabase.from('vendors').insert(editing);
    }
    setEditing(null);
    load();
  }

  async function toggleActive(v: Vendor) {
    await supabase.from('vendors').update({ is_active: !v.is_active }).eq('id', v.id);
    load();
  }

  async function toggleFeatured(v: Vendor) {
    await supabase.from('vendors').update({ is_featured: !v.is_featured }).eq('id', v.id);
    load();
  }

  async function move(i: number, dir: -1 | 1) {
    const j = i + dir;
    if (j < 0 || j >= list.length) return;
    const next = [...list];
    [next[i], next[j]] = [next[j], next[i]];
    setList(next);
    await supabase.rpc('admin_reorder_vendors', { p_ids: next.map((v) => v.id) });
  }

  async function remove(v: Vendor) {
    if (!confirm(`Remove vendor "${v.name}"? This will cascade to its products.`)) return;
    await supabase.from('vendors').delete().eq('id', v.id);
    load();
  }

  const [credVendor, setCredVendor] = useState<Vendor | null>(null);
  const [credEmail, setCredEmail] = useState('');
  const [credName, setCredName] = useState('');
  const [credPhone, setCredPhone] = useState('');
  const [credLoading, setCredLoading] = useState(false);
  const [credResult, setCredResult] = useState<{ email: string; password: string } | null>(null);
  const [credError, setCredError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  function openCredDialog(v: Vendor) {
    setCredVendor(v);
    setCredEmail('');
    setCredName(v.name + ' Owner');
    setCredPhone('');
    setCredResult(null);
    setCredError(null);
  }

  async function createVendorLogin() {
    if (!credVendor || !credEmail) return;
    setCredLoading(true);
    setCredError(null);
    const res = await adminCreateUser({
      email: credEmail,
      display_name: credName,
      phone: credPhone || undefined,
      role: 'vendor',
      vendor_id: credVendor.id,
    });
    setCredLoading(false);
    if (res.ok) {
      setCredResult({ email: res.email, password: res.password });
    } else {
      setCredError(res.message || res.error);
    }
  }

  function copyCredentials() {
    if (!credResult) return;
    navigator.clipboard.writeText(`Email: ${credResult.email}\nPassword: ${credResult.password}`);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  const filtered = list.filter((v) => (filter === 'all' ? true : v.category === filter));

  return (
    <div>
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Restaurants & Cafes</h1>
        <button className="btn-primary" onClick={() => setEditing({ ...EMPTY })}>
          <Plus size={16} /> Add vendor
        </button>
      </div>

      <div className="mt-4 flex flex-wrap gap-2">
        <Chip active={filter === 'all'} onClick={() => setFilter('all')}>All</Chip>
        {CATS.map((c) => (
          <Chip key={c} active={filter === c} onClick={() => setFilter(c)}>{c}</Chip>
        ))}
      </div>

      <div className="mt-4 overflow-hidden rounded-2xl border border-neutral-200 dark:border-neutral-800">
        <table className="w-full text-left text-sm">
          <thead className="bg-neutral-50 text-xs uppercase text-neutral-500 dark:bg-neutral-900">
            <tr>
              <th className="px-3 py-2">Order</th>
              <th className="px-3 py-2">Name</th>
              <th className="px-3 py-2">Category</th>
              <th className="px-3 py-2">Address</th>
              <th className="px-3 py-2 text-center">Active</th>
              <th className="px-3 py-2 text-center">Featured</th>
              <th className="px-3 py-2 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-neutral-100 dark:divide-neutral-900">
            {filtered.map((v, i) => (
              <tr key={v.id}>
                <td className="px-3 py-2">
                  <div className="flex items-center gap-1">
                    <button className="btn-ghost p-1" onClick={() => move(i, -1)}><ArrowUp size={14} /></button>
                    <button className="btn-ghost p-1" onClick={() => move(i, 1)}><ArrowDown size={14} /></button>
                  </div>
                </td>
                <td className="px-3 py-2 font-medium">{v.name}</td>
                <td className="px-3 py-2 capitalize">{v.category}</td>
                <td className="px-3 py-2 text-xs text-neutral-500">{v.dispatch_address}</td>
                <td className="px-3 py-2 text-center">
                  <button onClick={() => toggleActive(v)} className={v.is_active ? 'text-green-600' : 'text-neutral-400'}>
                    <Power size={16} />
                  </button>
                </td>
                <td className="px-3 py-2 text-center">
                  <button onClick={() => toggleFeatured(v)} className={v.is_featured ? 'text-amber-500' : 'text-neutral-400'}>
                    <Star size={16} fill={v.is_featured ? 'currentColor' : 'none'} />
                  </button>
                </td>
                <td className="px-3 py-2 text-right">
                  <button className="btn-ghost" onClick={() => openCredDialog(v)} title="Create login"><UserPlus size={14} /></button>
                  <button className="btn-ghost" onClick={() => setEditing(v)}><Pencil size={14} /></button>
                  <button className="btn-ghost text-red-600" onClick={() => remove(v)}><Trash2 size={14} /></button>
                </td>
              </tr>
            ))}
            {filtered.length === 0 && (
              <tr><td colSpan={7} className="px-3 py-6 text-center text-sm text-neutral-500">No vendors.</td></tr>
            )}
          </tbody>
        </table>
      </div>

      {editing && <EditDialog value={editing} onChange={setEditing} onSave={save} onClose={() => setEditing(null)} />}

      {credVendor && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="card w-full max-w-md p-5">
            <div className="text-lg font-semibold">Create Login — {credVendor.name}</div>

            {!credResult ? (
              <>
                <div className="mt-3 space-y-3">
                  <Field label="Email *">
                    <input className="input" type="email" placeholder="restaurant@example.com" value={credEmail} onChange={(e) => setCredEmail(e.target.value)} />
                  </Field>
                  <Field label="Display name">
                    <input className="input" value={credName} onChange={(e) => setCredName(e.target.value)} />
                  </Field>
                  <Field label="Phone">
                    <input className="input" placeholder="+91..." value={credPhone} onChange={(e) => setCredPhone(e.target.value)} />
                  </Field>
                </div>
                {credError && <div className="mt-3 rounded-xl bg-red-50 p-3 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200">{credError}</div>}
                <div className="mt-5 flex justify-end gap-2">
                  <button className="btn-outline" onClick={() => setCredVendor(null)}>Cancel</button>
                  <button className="btn-primary" disabled={!credEmail || credLoading} onClick={createVendorLogin}>
                    {credLoading ? 'Creating…' : 'Create account'}
                  </button>
                </div>
              </>
            ) : (
              <>
                <div className="mt-4 rounded-xl border border-green-200 bg-green-50 p-4 dark:border-green-800 dark:bg-green-900/20">
                  <div className="text-sm font-semibold text-green-800 dark:text-green-200">Account created!</div>
                  <div className="mt-2 space-y-1 font-mono text-sm">
                    <div><span className="text-neutral-500">Email:</span> {credResult.email}</div>
                    <div><span className="text-neutral-500">Password:</span> {credResult.password}</div>
                  </div>
                  <button onClick={copyCredentials} className="btn-outline mt-3 inline-flex items-center gap-1 text-xs">
                    {copied ? <><Check size={12} /> Copied!</> : <><Copy size={12} /> Copy credentials</>}
                  </button>
                </div>
                <p className="mt-3 text-xs text-neutral-500">Share these credentials with the restaurant owner. They can change the password after first login.</p>
                <div className="mt-4 flex justify-end">
                  <button className="btn-primary" onClick={() => setCredVendor(null)}>Done</button>
                </div>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function Chip({ children, active, onClick }: { children: React.ReactNode; active: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick} className={`chip ${active ? 'border-brand-600 bg-brand-50 text-brand-700 dark:bg-brand-600/10' : ''}`}>
      {children}
    </button>
  );
}

function EditDialog({ value, onChange, onSave, onClose }: {
  value: Partial<Vendor>;
  onChange: (v: Partial<Vendor>) => void;
  onSave: () => void;
  onClose: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="card max-h-[90vh] w-full max-w-xl overflow-y-auto p-5">
        <div className="text-lg font-semibold">{value.id ? 'Edit vendor' : 'Add vendor'}</div>
        <div className="mt-3 grid grid-cols-2 gap-3">
          <Field label="Name" className="col-span-2">
            <input className="input" value={value.name ?? ''} onChange={(e) => onChange({ ...value, name: e.target.value })} />
          </Field>
          <Field label="Slug">
            <input className="input" value={value.slug ?? ''} onChange={(e) => onChange({ ...value, slug: e.target.value })} />
          </Field>
          <Field label="Category">
            <select className="input" value={value.category ?? 'food'} onChange={(e) => onChange({ ...value, category: e.target.value as any })}>
              {CATS.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          </Field>
          <Field label="Description" className="col-span-2">
            <textarea className="input" rows={2} value={value.description ?? ''} onChange={(e) => onChange({ ...value, description: e.target.value })} />
          </Field>
          <Field label="Dispatch address" className="col-span-2">
            <input className="input" value={value.dispatch_address ?? ''} onChange={(e) => onChange({ ...value, dispatch_address: e.target.value })} />
          </Field>
          <Field label="Latitude">
            <input className="input" type="number" step="0.000001" value={value.latitude ?? 0} onChange={(e) => onChange({ ...value, latitude: parseFloat(e.target.value) })} />
          </Field>
          <Field label="Longitude">
            <input className="input" type="number" step="0.000001" value={value.longitude ?? 0} onChange={(e) => onChange({ ...value, longitude: parseFloat(e.target.value) })} />
          </Field>
          <Field label="Service radius (km)">
            <input className="input" type="number" step="0.1" value={value.service_radius_km ?? 7} onChange={(e) => onChange({ ...value, service_radius_km: parseFloat(e.target.value) })} />
          </Field>
          <Field label="Prep time (min)">
            <input className="input" type="number" value={value.prep_time_minutes ?? 20} onChange={(e) => onChange({ ...value, prep_time_minutes: parseInt(e.target.value || '0', 10) })} />
          </Field>
          <Field label="Min order (paise)">
            <input className="input" type="number" value={value.min_order_paise ?? 0} onChange={(e) => onChange({ ...value, min_order_paise: parseInt(e.target.value || '0', 10) })} />
          </Field>
        </div>
        <div className="mt-5 flex justify-end gap-2">
          <button className="btn-outline" onClick={onClose}>Cancel</button>
          <button className="btn-primary" onClick={onSave}>Save</button>
        </div>
      </div>
    </div>
  );
}

function Field({ label, className = '', children }: { label: string; className?: string; children: React.ReactNode }) {
  return (
    <label className={`block ${className}`}>
      <div className="mb-1 text-xs font-semibold text-neutral-500">{label}</div>
      {children}
    </label>
  );
}
