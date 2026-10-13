import { createClient } from '@supabase/supabase-js';
import { readFile } from 'node:fs/promises';
const config = JSON.parse(await readFile(new URL('../config/local.json', import.meta.url)));
const client = createClient(config.SUPABASE_URL, config.SUPABASE_ANON_KEY,
  { auth: { persistSession: false, autoRefreshToken: false } });
const channel = client.channel(`readiness-${crypto.randomUUID()}`, { config: { broadcast: { self: true } } });
try {
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Realtime probe timed out')), 15000);
    channel.on('broadcast', { event: 'readiness' }, () => { clearTimeout(timeout); resolve(); });
    channel.subscribe(async status => {
      if (status === 'SUBSCRIBED') await channel.send({ type: 'broadcast', event: 'readiness', payload: { probe: true } });
      if (status === 'CHANNEL_ERROR') { clearTimeout(timeout); reject(new Error('Realtime channel rejected')); }
    });
  });
  console.log(JSON.stringify({ realtime_websocket_roundtrip: true, database_rows_changed: false }));
} finally { await client.removeAllChannels(); client.realtime.disconnect(); }
