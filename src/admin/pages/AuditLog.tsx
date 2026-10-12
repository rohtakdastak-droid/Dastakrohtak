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
      <h1 className="text-2xl font-bold">Audit log</h1>
      <div className="mt-4 overflow-x-auto rounded-2xl border border-neutral-200 dark:border-neutral-800">
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
