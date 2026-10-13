import { useEffect, useRef, useState } from 'react';
import { Bell, Check, BellRing } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useSession } from '../lib/auth';
import { pushSupported, subscribePush } from '../lib/push';
import { isNativePush, registerNativePush } from '../lib/nativePush';

type Notif = {
  id: string;
  type: string;
  title: string;
  body: string | null;
  order_id: string | null;
  read_at: string | null;
  created_at: string;
};

export default function NotificationBell({ className = '', orderLinkBase = '/orders' }: { className?: string; orderLinkBase?: string }) {
  const { session } = useSession();
  const [open, setOpen] = useState(false);
  const [list, setList] = useState<Notif[]>([]);
  const ref = useRef<HTMLDivElement | null>(null);

  async function load() {
    if (!session) return;
    const { data } = await supabase
      .from('notifications')
      .select('*')
      .eq('user_id', session.user.id)
      .order('created_at', { ascending: false })
      .limit(30);
    setList((data as Notif[]) ?? []);
  }

  useEffect(() => {
    load();
    if (!session) return;
    const ch = supabase
      .channel(`notif:${session.user.id}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${session.user.id}` },
        (payload) => {
          setList((prev) => [payload.new as Notif, ...prev]);
          if ('Notification' in window && Notification.permission === 'granted') {
            try {
              new Notification((payload.new as Notif).title, { body: (payload.new as Notif).body ?? '' });
            } catch { /* ignore */ }
          }
        }
      )
      .subscribe();
    return () => void supabase.removeChannel(ch);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session?.user.id]);

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (!ref.current?.contains(e.target as Node)) setOpen(false);
    };
    if (open) document.addEventListener('mousedown', onClick);
    return () => document.removeEventListener('mousedown', onClick);
  }, [open]);

  const unread = list.filter((n) => !n.read_at).length;

  async function markAll() {
    if (!session || unread === 0) return;
    const ids = list.filter((n) => !n.read_at).map((n) => n.id);
    await supabase.from('notifications').update({ read_at: new Date().toISOString() }).in('id', ids);
    load();
  }

  const [pushReady, setPushReady] = useState(false);

  useEffect(() => {
    if (!session) return;
    if (isNativePush()) {
      registerNativePush(session.user.id).then((ok) => setPushReady(ok));
    } else if (pushSupported() && 'Notification' in window && Notification.permission === 'granted') {
      subscribePush(session.user.id).then((ok) => setPushReady(ok));
    }
  }, [session?.user.id]);

  async function requestPushPermission() {
    if (!session) return;
    if (isNativePush()) {
      const ok = await registerNativePush(session.user.id);
      setPushReady(ok);
    } else if ('Notification' in window && Notification.permission === 'default') {
      const perm = await Notification.requestPermission();
      if (perm === 'granted' && pushSupported()) {
        const ok = await subscribePush(session.user.id);
        setPushReady(ok);
      }
    }
  }

  if (!session) return null;

  return (
    <div ref={ref} className={`relative ${className}`}>
      <button
        onClick={() => {
          setOpen((v) => !v);
          requestPushPermission();
        }}
        className="relative rounded-full p-2 hover:bg-neutral-100 dark:hover:bg-neutral-900"
        aria-label="Notifications"
      >
        <Bell size={18} />
        {unread > 0 && (
          <span className="absolute right-0.5 top-0.5 min-w-[16px] rounded-full bg-brand-600 px-1 text-center text-[10px] font-bold leading-4 text-white">
            {unread > 9 ? '9+' : unread}
          </span>
        )}
      </button>

      {open && (
        <div className="absolute right-0 top-11 z-50 w-80 overflow-hidden rounded-2xl border border-neutral-200 bg-white shadow-lg dark:border-neutral-800 dark:bg-neutral-950">
          <div className="flex items-center justify-between border-b border-neutral-200 px-3 py-2 dark:border-neutral-800">
            <div className="text-sm font-semibold">Notifications</div>
            <div className="flex items-center gap-2">
              {(isNativePush() || pushSupported()) && !pushReady && (typeof Notification === 'undefined' || Notification.permission !== 'denied') && (
                <button onClick={requestPushPermission} className="inline-flex items-center gap-1 text-xs text-brand-600" title="Enable push notifications">
                  <BellRing size={12} /> Enable push
                </button>
              )}
              {unread > 0 && (
                <button onClick={markAll} className="inline-flex items-center gap-1 text-xs text-brand-600">
                  <Check size={12} /> Mark all read
                </button>
              )}
            </div>
          </div>
          <div className="max-h-80 overflow-y-auto">
            {list.length === 0 && (
              <div className="p-6 text-center text-xs text-neutral-500">No notifications yet.</div>
            )}
            {list.map((n) => {
              const inner = (
                <div className={`flex items-start gap-2 border-b border-neutral-100 px-3 py-2.5 last:border-0 dark:border-neutral-900 ${!n.read_at ? 'bg-brand-50/40 dark:bg-brand-600/5' : ''}`}>
                  <div className={`mt-1 h-2 w-2 shrink-0 rounded-full ${!n.read_at ? 'bg-brand-600' : 'bg-neutral-300'}`} />
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-medium">{n.title}</div>
                    {n.body && <div className="line-clamp-2 text-xs text-neutral-500">{n.body}</div>}
                    <div className="mt-0.5 text-[11px] text-neutral-400">{new Date(n.created_at).toLocaleString()}</div>
                  </div>
                </div>
              );
              return n.order_id ? (
                <Link key={n.id} to={`${orderLinkBase}/${n.order_id}`} onClick={() => setOpen(false)}>{inner}</Link>
              ) : (
                <div key={n.id}>{inner}</div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
