import { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';

export default function AuditLog() {
  const [rows, setRows] = useState<any[]>([]);

  useEffect(() => {
    supabase
      .from('admin_audit_logs')
      .select('*,profiles:actor_id(display_name)')
      .order('created_at', { ascending: false })
      .limit(200)
      .then(({ data }) => setRows(data ?? []));
  }, []);

  return (
    <div>
      <h1 className="text-xl font-bold md:text-2xl">Audit log</h1>

      {/* Mobile card layout */}
      <div className="mt-4 space-y-2 md:hidden">
        {rows.map((r) => (
          <div key={r.id} className="card p-3">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0 flex-1">
                <div className="font-mono text-xs font-medium">{r.action}</div>
                <div className="mt-0.5 text-xs text-neutral-500">{r.entity}{r.entity_id ? ` · ${String(r.entity_id).slice(0, 8)}` : ''}</div>
                {r.reason && <div className="mt-1 text-xs text-neutral-400">{r.reason}</div>}
              </div>
              <div className="text-right shrink-0">
                <div className="text-[10px] text-neutral-400">{r.profiles?.display_name ?? r.actor_id?.slice(0, 8) ?? 'system'}</div>
                <div className="text-[10px] text-neutral-400">{new Date(r.created_at).toLocaleString()}</div>
              </div>
            </div>
          </div>
        ))}
        {rows.length === 0 && <div className="py-6 text-center text-sm text-neutral-500">No audit entries yet.</div>}
      </div>

      {/* Desktop table */}
      <div className="mt-4 hidden overflow-x-auto rounded-2xl border border-neutral-200 dark:border-neutral-800 md:block">
        <table className="w-full text-left text-sm">
          <thead className="bg-neutral-50 text-xs uppercase text-neutral-500 dark:bg-neutral-900">
            <tr>
              <th className="px-3 py-2">When</th>
              <th className="px-3 py-2">Actor</th>
              <th className="px-3 py-2">Action</th>
              <th className="px-3 py-2">Entity</th>
              <th className="px-3 py-2">Reason</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-neutral-100 dark:divide-neutral-900">
            {rows.map((r) => (
              <tr key={r.id}>
                <td className="px-3 py-2 text-xs text-neutral-500">{new Date(r.created_at).toLocaleString()}</td>
                <td className="px-3 py-2 text-xs">{r.profiles?.display_name ?? r.actor_id?.slice(0, 8) ?? 'system'}</td>
                <td className="px-3 py-2 font-mono text-xs">{r.action}</td>
                <td className="px-3 py-2 text-xs">{r.entity}{r.entity_id ? ` · ${String(r.entity_id).slice(0, 8)}` : ''}</td>
                <td className="px-3 py-2 text-xs text-neutral-500">{r.reason ?? '—'}</td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr><td colSpan={5} className="px-3 py-6 text-center text-sm text-neutral-500">No audit entries yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
