import { useEffect, useState, useRef } from 'react';
import { Save, QrCode, Upload, Image, Trash2 } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatRupees } from '../../lib/deliveryFee';

type Rate = { id?: string; min_km: number; max_km: number; fee_paise: number };

export default function Settings() {
  const [pay, setPay] = useState<any>(null);
  const [rates, setRates] = useState<Rate[]>([]);
  const [overflow, setOverflow] = useState<{ ceiling_km: number; base_fee_paise: number; per_km_paise: number } | null>(null);
  const [tax, setTax] = useState(0);
  const [msg, setMsg] = useState<string | null>(null);

  // QR upload
  const fileRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const [qrPreview, setQrPreview] = useState<string | null>(null);

  async function load() {
    const [p, r, o, t] = await Promise.all([
      supabase.from('payment_settings').select('*').eq('id', true).single(),
      supabase.from('delivery_rate_rules').select('*').order('min_km'),
      supabase.from('delivery_overflow_rule').select('*').eq('id', true).single(),
      supabase.from('app_settings').select('*').eq('key', 'tax_percent').single(),
    ]);
    setPay(p.data);
    setRates((r.data as Rate[]) ?? []);
    setOverflow(o.data as any);
    setTax(Number((t.data?.value as any) ?? 0));

    if (p.data?.qr_image_path) {
      const { data: urlData } = supabase.storage.from('payment-qr').getPublicUrl(p.data.qr_image_path);
      if (urlData?.publicUrl) setQrPreview(urlData.publicUrl);
    }
  }
  useEffect(() => { load(); }, []);

  async function uploadQr(file: File) {
    setUploading(true);
    setMsg(null);

    const ext = file.name.split('.').pop()?.toLowerCase() ?? 'png';
    const path = `qr-${Date.now()}.${ext}`;

    const { error: upErr } = await supabase.storage
      .from('payment-qr')
      .upload(path, file, { cacheControl: '3600', upsert: true });

    if (upErr) {
      setMsg(`Upload failed: ${upErr.message}`);
      setUploading(false);
      return;
    }

    const { data: urlData } = supabase.storage.from('payment-qr').getPublicUrl(path);
    setQrPreview(urlData?.publicUrl ?? null);
    setPay((prev: any) => ({ ...prev, qr_image_path: path }));
    setUploading(false);
    setMsg('QR image uploaded! Don\'t forget to save payment settings.');
  }

  async function removeQr() {
    if (pay?.qr_image_path) {
      await supabase.storage.from('payment-qr').remove([pay.qr_image_path]);
    }
    setPay((prev: any) => ({ ...prev, qr_image_path: null }));
    setQrPreview(null);
    setMsg('QR image removed. Save payment settings to confirm.');
  }

  async function savePay() {
    setMsg(null);
    const { error } = await supabase.from('payment_settings').update({
      upi_vpa: pay.upi_vpa,
      payee_name: pay.payee_name,
      qr_image_path: pay.qr_image_path,
      instructions: pay.instructions,
      cod_enabled: pay.cod_enabled,
      verification_mode: pay.verification_mode,
    }).eq('id', true);
    setMsg(error ? error.message : 'Payment settings saved.');
  }

  async function saveRates() {
    setMsg(null);
    const rows = rates.map((r) => ({ min_km: r.min_km, max_km: r.max_km, fee_paise: r.fee_paise }));
    const { error } = await supabase.rpc('admin_replace_rate_table', { p_rows: rows });
    if (error) { setMsg(error.message); return; }
    if (overflow) {
      await supabase.from('delivery_overflow_rule').update(overflow).eq('id', true);
    }
    setMsg('Delivery rates saved.');
  }

  async function saveTax() {
    const { error } = await supabase.from('app_settings').upsert({ key: 'tax_percent', value: tax });
    setMsg(error ? error.message : 'Tax saved.');
  }

  if (!pay || !overflow) return <div className="p-6 text-sm text-neutral-500">Loading…</div>;

  return (
    <div className="space-y-4 md:space-y-6">
      <h1 className="text-xl font-bold md:text-2xl">Settings</h1>

      <section className="card p-3 md:p-5">
        <div className="flex items-center gap-2 text-sm font-semibold"><QrCode size={16} /> Payment (UPI QR)</div>
        <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
          <F label="UPI VPA">
            <input className="input" value={pay.upi_vpa ?? ''} onChange={(e) => setPay({ ...pay, upi_vpa: e.target.value })} />
          </F>
          <F label="Payee name">
            <input className="input" value={pay.payee_name ?? ''} onChange={(e) => setPay({ ...pay, payee_name: e.target.value })} />
          </F>

          {/* QR Image Upload */}
          <div className="sm:col-span-2">
            <div className="mb-1 text-xs font-semibold text-neutral-500">UPI QR Image</div>
            <div className="flex flex-col items-start gap-4 sm:flex-row">
              {/* Preview */}
              <div className="relative flex h-36 w-36 shrink-0 items-center justify-center overflow-hidden rounded-2xl border-2 border-dashed border-neutral-200 bg-neutral-50 dark:border-neutral-700 dark:bg-neutral-800 sm:h-40 sm:w-40">
                {qrPreview ? (
                  <>
                    <img src={qrPreview} alt="UPI QR" className="h-full w-full object-contain p-2" />
                    <button
                      onClick={removeQr}
                      className="absolute right-1.5 top-1.5 rounded-full bg-red-500 p-1 text-white shadow transition hover:bg-red-600"
                      title="Remove QR"
                    >
                      <Trash2 size={12} />
                    </button>
                  </>
                ) : (
                  <div className="flex flex-col items-center gap-1 text-neutral-400">
                    <Image size={28} />
                    <span className="text-[10px]">No QR uploaded</span>
                  </div>
                )}
              </div>

              {/* Upload controls */}
              <div className="flex-1 space-y-2">
                <input
                  ref={fileRef}
                  type="file"
                  accept="image/png,image/jpeg,image/webp"
                  className="hidden"
                  onChange={(e) => {
                    const f = e.target.files?.[0];
                    if (f) uploadQr(f);
                    e.target.value = '';
                  }}
                />
                <button
                  className="btn-outline w-full"
                  onClick={() => fileRef.current?.click()}
                  disabled={uploading}
                >
                  <Upload size={14} /> {uploading ? 'Uploading…' : 'Upload QR image'}
                </button>
                <p className="text-[11px] text-neutral-400">
                  PNG, JPG or WebP. This QR code will be shown to customers at checkout for UPI payment.
                </p>
                {pay.qr_image_path && (
                  <div className="rounded-lg bg-neutral-100 px-2 py-1 text-[11px] text-neutral-500 dark:bg-neutral-800">
                    Path: {pay.qr_image_path}
                  </div>
                )}
              </div>
            </div>
          </div>

          <F label="Instructions" className="sm:col-span-2">
            <textarea className="input" rows={2} value={pay.instructions ?? ''} onChange={(e) => setPay({ ...pay, instructions: e.target.value })} />
          </F>
          <F label="Verification mode">
            <select className="input" value={pay.verification_mode} onChange={(e) => setPay({ ...pay, verification_mode: e.target.value })}>
              <option value="manual">Manual (admin verifies)</option>
              <option value="gateway">Gateway webhook (not wired)</option>
            </select>
          </F>
          <F label="COD enabled?">
            <select className="input" value={pay.cod_enabled ? '1' : '0'} onChange={(e) => setPay({ ...pay, cod_enabled: e.target.value === '1' })}>
              <option value="0">OFF (default)</option>
              <option value="1">ON</option>
            </select>
          </F>
        </div>
        <button className="btn-primary mt-4" onClick={savePay}><Save size={14} /> Save payment settings</button>
      </section>

      <section className="card p-3 md:p-5">
        <div className="text-sm font-semibold">Delivery rate table</div>
        <p className="mt-1 text-xs text-neutral-500">Bands are evaluated as (min_km, max_km]. Changing this affects only future orders.</p>
        <div className="mt-3 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="bg-neutral-50 text-xs uppercase text-neutral-500 dark:bg-neutral-900">
              <tr>
                <th className="px-2 py-1">Min km</th>
                <th className="px-2 py-1">Max km</th>
                <th className="px-2 py-1">Fee (paise)</th>
                <th className="px-2 py-1 text-right">Fee</th>
              </tr>
            </thead>
            <tbody>
              {rates.map((r, i) => (
                <tr key={i}>
                  <td className="px-2 py-1"><input className="input py-1" type="number" step="0.1" value={r.min_km} onChange={(e) => updateRate(i, 'min_km', parseFloat(e.target.value))} /></td>
                  <td className="px-2 py-1"><input className="input py-1" type="number" step="0.1" value={r.max_km} onChange={(e) => updateRate(i, 'max_km', parseFloat(e.target.value))} /></td>
                  <td className="px-2 py-1"><input className="input py-1" type="number" value={r.fee_paise} onChange={(e) => updateRate(i, 'fee_paise', parseInt(e.target.value || '0', 10))} /></td>
                  <td className="px-2 py-1 text-right text-xs text-neutral-500">{formatRupees(r.fee_paise)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="mt-4 rounded-xl bg-neutral-50 p-3 dark:bg-neutral-900">
          <div className="text-xs font-semibold text-neutral-500">Overflow (above ceiling)</div>
          <div className="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-3">
            <F label="Ceiling km">
              <input className="input" type="number" step="0.1" value={overflow.ceiling_km} onChange={(e) => setOverflow({ ...overflow, ceiling_km: parseFloat(e.target.value) })} />
            </F>
            <F label="Base fee (paise)">
              <input className="input" type="number" value={overflow.base_fee_paise} onChange={(e) => setOverflow({ ...overflow, base_fee_paise: parseInt(e.target.value || '0', 10) })} />
            </F>
            <F label="Per extra km (paise)">
              <input className="input" type="number" value={overflow.per_km_paise} onChange={(e) => setOverflow({ ...overflow, per_km_paise: parseInt(e.target.value || '0', 10) })} />
            </F>
          </div>
        </div>
        <button className="btn-primary mt-4" onClick={saveRates}><Save size={14} /> Save delivery rates</button>
      </section>

      <section className="card p-3 md:p-5">
        <div className="text-sm font-semibold">Tax</div>
        <div className="mt-2 flex flex-col gap-2 sm:flex-row sm:items-center">
          <input className="input w-full sm:w-32" type="number" step="0.1" value={tax} onChange={(e) => setTax(parseFloat(e.target.value || '0'))} />
          <span className="text-xs text-neutral-500 sm:text-sm">% applied at checkout (0 = off)</span>
          <button className="btn-outline shrink-0" onClick={saveTax}><Save size={14} /> Save</button>
        </div>
      </section>

      {msg && <div className="animate-scale-in rounded-xl bg-neutral-100 p-3 text-sm dark:bg-neutral-900">{msg}</div>}
    </div>
  );

  function updateRate(i: number, k: keyof Rate, v: number) {
    setRates((prev) => prev.map((r, idx) => (idx === i ? { ...r, [k]: v } : r)));
  }
}

function F({ label, className = '', children }: { label: string; className?: string; children: React.ReactNode }) {
  return (
    <label className={`block ${className}`}>
      <div className="mb-1 text-xs font-semibold text-neutral-500">{label}</div>
      {children}
    </label>
  );
}
