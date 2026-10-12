import { useEffect, useState } from 'react';
import { Plus, Pencil, Trash2, Power } from 'lucide-react';
import { supabase, type Product, type Vendor } from '../../lib/supabase';
import { formatRupees } from '../../lib/deliveryFee';

const EMPTY: Partial<Product> = {
  name: '', description: '', price_paise: 0, sale_price_paise: null,
  diet: 'unknown', is_available: true,
};

export default function Products() {
  const [vendors, setVendors] = useState<Vendor[]>([]);
  const [vendorId, setVendorId] = useState<string>('');
  const [products, setProducts] = useState<Product[]>([]);
  const [editing, setEditing] = useState<Partial<Product> | null>(null);

  useEffect(() => {
    supabase.from('vendors').select('*').order('name').then(({ data }) => {
      const vs = (data as Vendor[]) ?? [];
      setVendors(vs);
      if (vs[0]) setVendorId(vs[0].id);
    });
  }, []);

  async function loadProducts() {
    if (!vendorId) return;
    const { data } = await supabase.from('products').select('*').eq('vendor_id', vendorId).order('name');
    setProducts((data as Product[]) ?? []);
  }
  useEffect(() => { loadProducts(); }, [vendorId]);

  async function save() {
    if (!editing || !vendorId) return;
    if (editing.id) {
      const { id, vendor_id: _, ...patch } = editing as Product;
      await supabase.from('products').update(patch).eq('id', id);
    } else {
      await supabase.from('products').insert({ ...editing, vendor_id: vendorId });
    }
    setEditing(null);
    loadProducts();
  }

  async function toggle(p: Product) {
    await supabase.from('products').update({ is_available: !p.is_available }).eq('id', p.id);
    loadProducts();
  }

  async function remove(p: Product) {
    if (!confirm(`Delete "${p.name}"?`)) return;
    await supabase.from('products').delete().eq('id', p.id);
    loadProducts();
  }

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-2xl font-bold">Products</h1>
        <div className="flex items-center gap-2">
          <select className="input w-auto" value={vendorId} onChange={(e) => setVendorId(e.target.value)}>
            {vendors.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
          </select>
          <button className="btn-primary" onClick={() => setEditing({ ...EMPTY })}>
            <Plus size={16} /> Add product
          </button>
        </div>
      </div>

      <div className="mt-4 overflow-hidden rounded-2xl border border-neutral-200 dark:border-neutral-800">
        <table className="w-full text-left text-sm">
          <thead className="bg-neutral-50 text-xs uppercase text-neutral-500 dark:bg-neutral-900">
            <tr>
              <th className="px-3 py-2">Name</th>
              <th className="px-3 py-2">Diet</th>
              <th className="px-3 py-2 text-right">Price</th>
              <th className="px-3 py-2 text-right">Sale</th>
              <th className="px-3 py-2 text-center">Available</th>
              <th className="px-3 py-2 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-neutral-100 dark:divide-neutral-900">
            {products.map((p) => (
              <tr key={p.id}>
                <td className="px-3 py-2">
                  <div className="font-medium">{p.name}</div>
                  <div className="line-clamp-1 text-xs text-neutral-500">{p.description}</div>
                </td>
                <td className="px-3 py-2 capitalize">{p.diet.replace('_', ' ')}</td>
                <td className="px-3 py-2 text-right">{formatRupees(p.price_paise)}</td>
                <td className="px-3 py-2 text-right">{p.sale_price_paise ? formatRupees(p.sale_price_paise) : '—'}</td>
                <td className="px-3 py-2 text-center">
                  <button onClick={() => toggle(p)} className={p.is_available ? 'text-green-600' : 'text-neutral-400'}>
                    <Power size={16} />
                  </button>
                </td>
                <td className="px-3 py-2 text-right">
                  <button className="btn-ghost" onClick={() => setEditing(p)}><Pencil size={14} /></button>
                  <button className="btn-ghost text-red-600" onClick={() => remove(p)}><Trash2 size={14} /></button>
                </td>
              </tr>
            ))}
            {products.length === 0 && (
              <tr><td colSpan={6} className="px-3 py-6 text-center text-sm text-neutral-500">No products yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>

      {editing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="card w-full max-w-lg p-5">
            <div className="text-lg font-semibold">{editing.id ? 'Edit' : 'Add'} product</div>
            <div className="mt-3 grid grid-cols-2 gap-3">
              <F label="Name" className="col-span-2">
                <input className="input" value={editing.name ?? ''} onChange={(e) => setEditing({ ...editing, name: e.target.value })} />
              </F>
              <F label="Description" className="col-span-2">
                <textarea className="input" rows={2} value={editing.description ?? ''} onChange={(e) => setEditing({ ...editing, description: e.target.value })} />
              </F>
              <F label="Price (paise)">
                <input className="input" type="number" value={editing.price_paise ?? 0} onChange={(e) => setEditing({ ...editing, price_paise: parseInt(e.target.value || '0', 10) })} />
              </F>
              <F label="Sale price (paise, optional)">
                <input className="input" type="number" value={editing.sale_price_paise ?? ''} onChange={(e) => setEditing({ ...editing, sale_price_paise: e.target.value ? parseInt(e.target.value, 10) : null })} />
              </F>
              <F label="Diet">
                <select className="input" value={editing.diet ?? 'unknown'} onChange={(e) => setEditing({ ...editing, diet: e.target.value as any })}>
                  <option value="veg">Veg</option>
                  <option value="non_veg">Non-veg</option>
                  <option value="egg">Egg</option>
                  <option value="unknown">Unknown</option>
                </select>
              </F>
              <F label="Available">
                <select className="input" value={editing.is_available ? '1' : '0'} onChange={(e) => setEditing({ ...editing, is_available: e.target.value === '1' })}>
                  <option value="1">Yes</option>
                  <option value="0">No</option>
                </select>
              </F>
            </div>
            <div className="mt-5 flex justify-end gap-2">
              <button className="btn-outline" onClick={() => setEditing(null)}>Cancel</button>
              <button className="btn-primary" onClick={save}>Save</button>
            </div>
          </div>
        </div>
      )}
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
