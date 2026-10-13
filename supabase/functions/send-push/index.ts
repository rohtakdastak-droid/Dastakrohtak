// supabase/functions/send-push/index.ts
//
// Receives a notification payload from the DB trigger (via pg_net) and sends
// Web Push to every registered device for that user.
//
// Secrets required:
//   PUSH_WEBHOOK_TOKEN  — shared secret (must match app.push_webhook_token in DB)
//   VAPID_PUBLIC_KEY    — base64url-encoded VAPID public key
//   VAPID_PRIVATE_KEY   — base64url-encoded VAPID private key
//   VAPID_SUBJECT       — mailto: or https:// contact for the push service
//   FCM_SERVICE_ACCOUNT — JSON string of the Firebase service account private key
//   FCM_PROJECT_ID      — Firebase project ID (e.g. dastak-5ad52)
//
// Deploy:
//   supabase functions deploy send-push

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: { 'content-type': 'application/json', ...CORS, ...(init.headers ?? {}) },
  });
}

// ─── Minimal Web Push (VAPID + encrypted payload) ─────────────────────────

function base64urlToUint8(s: string): Uint8Array {
  const b = atob(s.replace(/-/g, '+').replace(/_/g, '/') + '=='.slice(0, (4 - (s.length % 4)) % 4));
  return Uint8Array.from(b, (c) => c.charCodeAt(0));
}

function uint8ToBase64url(u: Uint8Array): string {
  let s = '';
  u.forEach((b) => (s += String.fromCharCode(b)));
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function importVapidKeys(pubB64: string, privB64: string) {
  const pubRaw = base64urlToUint8(pubB64);
  const privRaw = base64urlToUint8(privB64);
  const publicKey = await crypto.subtle.importKey('raw', pubRaw, { name: 'ECDSA', namedCurve: 'P-256' }, true, []);
  const privateKey = await crypto.subtle.importKey(
    'jwk',
    { kty: 'EC', crv: 'P-256', x: uint8ToBase64url(pubRaw.slice(1, 33)), y: uint8ToBase64url(pubRaw.slice(33, 65)), d: uint8ToBase64url(privRaw), ext: true },
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  );
  return { publicKey, privateKey, pubRaw };
}

async function createVapidJwt(audience: string, subject: string, privateKey: CryptoKey): Promise<string> {
  const header = uint8ToBase64url(new TextEncoder().encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const now = Math.floor(Date.now() / 1000);
  const payload = uint8ToBase64url(new TextEncoder().encode(JSON.stringify({ aud: audience, exp: now + 86400, sub: subject })));
  const input = new TextEncoder().encode(`${header}.${payload}`);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, privateKey, input));
  // DER → raw r||s (each 32 bytes)
  const r = sig.slice(0, 32);
  const s = sig.slice(32, 64);
  return `${header}.${payload}.${uint8ToBase64url(new Uint8Array([...r, ...s]))}`;
}

// Encrypt payload per RFC 8291 (aes128gcm).
async function encryptPayload(
  clientPubB64: string,
  authSecretB64: string,
  payload: Uint8Array
): Promise<{ ciphertext: Uint8Array; localPubRaw: Uint8Array; salt: Uint8Array }> {
  const clientPub = base64urlToUint8(clientPubB64);
  const authSecret = base64urlToUint8(authSecretB64);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const localKP = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const localPubRaw = new Uint8Array(await crypto.subtle.exportKey('raw', localKP.publicKey));
  const clientPubKey = await crypto.subtle.importKey('raw', clientPub, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const sharedSecret = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: clientPubKey }, localKP.privateKey, 256));

  const authInfo = new TextEncoder().encode('WebPush: info\0');
  const ikm_info = new Uint8Array([...authInfo, ...clientPub, ...localPubRaw]);
  const prkKey = await crypto.subtle.importKey('raw', authSecret, { name: 'HKDF' }, false, ['deriveBits']);
  const prk = new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt: sharedSecret, info: ikm_info }, prkKey, 256)
  );
  const prkCK = await crypto.subtle.importKey('raw', prk, { name: 'HKDF' }, false, ['deriveBits']);
  const cekInfo = new TextEncoder().encode('Content-Encoding: aes128gcm\0');
  const cek = new Uint8Array(await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info: cekInfo }, prkCK, 128));
  const nonceInfo = new TextEncoder().encode('Content-Encoding: nonce\0');
  const nonce = new Uint8Array(await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info: nonceInfo }, prkCK, 96));

  const padded = new Uint8Array([...payload, 2]); // delimiter byte
  const aesCK = await crypto.subtle.importKey('raw', cek, { name: 'AES-GCM' }, false, ['encrypt']);
  const encrypted = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aesCK, padded));

  // aes128gcm header: salt(16) + rs(4) + idlen(1) + keyid(65) + ciphertext
  const rs = new DataView(new ArrayBuffer(4));
  rs.setUint32(0, 4096);
  const header = new Uint8Array([...salt, ...new Uint8Array(rs.buffer), localPubRaw.length, ...localPubRaw]);
  return { ciphertext: new Uint8Array([...header, ...encrypted]), localPubRaw, salt };
}

async function sendPushToEndpoint(
  endpoint: string,
  p256dh: string,
  auth: string,
  payloadJson: string,
  vapidPrivateKey: CryptoKey,
  vapidPubRaw: Uint8Array,
  vapidSubject: string
): Promise<{ ok: boolean; status: number }> {
  const url = new URL(endpoint);
  const audience = `${url.protocol}//${url.host}`;
  const jwt = await createVapidJwt(audience, vapidSubject, vapidPrivateKey);
  const { ciphertext } = await encryptPayload(p256dh, auth, new TextEncoder().encode(payloadJson));

  const resp = await fetch(endpoint, {
    method: 'POST',
    headers: {
      Authorization: `vapid t=${jwt}, k=${uint8ToBase64url(vapidPubRaw)}`,
      'Content-Encoding': 'aes128gcm',
      'Content-Type': 'application/octet-stream',
      TTL: '86400',
    },
    body: ciphertext,
  });
  return { ok: resp.ok, status: resp.status };
}

// ─── FCM V1 auth (service account → OAuth2 access token) ────────────────

async function getFcmAccessToken(serviceAccountJson: string): Promise<string | null> {
  try {
    const sa = JSON.parse(serviceAccountJson);
    const now = Math.floor(Date.now() / 1000);
    const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    const claim = btoa(JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    })).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

    const input = new TextEncoder().encode(`${header}.${claim}`);

    const pemBody = sa.private_key
      .replace(/-----BEGIN PRIVATE KEY-----/, '')
      .replace(/-----END PRIVATE KEY-----/, '')
      .replace(/\s/g, '');
    const keyBuf = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
    const cryptoKey = await crypto.subtle.importKey(
      'pkcs8', keyBuf, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']
    );

    const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, input));
    let sigB64 = '';
    sig.forEach((b) => (sigB64 += String.fromCharCode(b)));
    sigB64 = btoa(sigB64).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

    const jwt = `${header}.${claim}.${sigB64}`;

    const resp = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    });

    if (!resp.ok) return null;
    const data = await resp.json();
    return data.access_token ?? null;
  } catch {
    return null;
  }
}

// ─── Handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, { status: 405 });

  const token = Deno.env.get('PUSH_WEBHOOK_TOKEN');
  const bearer = req.headers.get('authorization')?.replace('Bearer ', '');
  if (!token || bearer !== token) return json({ error: 'unauthorized' }, { status: 401 });

  // Authenticated diagnostics never send a notification or return credentials.
  if (new URL(req.url).searchParams.get('health') === '1') {
    const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
    const project = Deno.env.get('FCM_PROJECT_ID');
    let matchingProject = false;
    try { matchingProject = JSON.parse(raw ?? '{}').project_id === project; } catch { /* invalid configuration */ }
    const accessToken = raw && matchingProject ? await getFcmAccessToken(raw) : null;
    let fcmApiOk = false;
    if (accessToken) {
      const validation = await fetch(`https://fcm.googleapis.com/v1/projects/${project}/messages:send`, {
        method: 'POST', signal: AbortSignal.timeout(10000),
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ validate_only: true, message: {
          topic: 'dastak_configuration_validation', notification: { title: 'Configuration validation' }
        } }),
      });
      fcmApiOk = validation.ok;
    }
    return json({ fcm_oauth_ok: Boolean(accessToken), project_matches: matchingProject,
      fcm_api_validation_ok: fcmApiOk }, { status: fcmApiOk ? 200 : 503 });
  }

  const VAPID_PUBLIC = Deno.env.get('VAPID_PUBLIC_KEY');
  const VAPID_PRIVATE = Deno.env.get('VAPID_PRIVATE_KEY');
  const VAPID_SUBJECT = Deno.env.get('VAPID_SUBJECT') ?? 'mailto:hello@dastak.app';

  let payload: any;
  try { payload = await req.json(); } catch { return json({ error: 'bad_json' }, { status: 400 }); }

  const { user_id, title, body, order_id, type } = payload;
  if (!user_id || !title) return json({ error: 'bad_input' }, { status: 400 });

  const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
  const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: subs } = await sb
    .from('push_subscriptions')
    .select('endpoint, p256dh, auth')
    .eq('user_id', user_id);

  // ─── FCM V1 (native Android/iOS) ────────────────────────────────────────
  const FCM_SA_RAW = Deno.env.get('FCM_SERVICE_ACCOUNT');
  const FCM_PROJECT = Deno.env.get('FCM_PROJECT_ID');
  let fcmSent = 0;

  if (FCM_SA_RAW && FCM_PROJECT) {
    const { data: fcmTokens } = await sb
      .from('fcm_tokens')
      .select('token')
      .eq('user_id', user_id);

    if (fcmTokens && fcmTokens.length > 0) {
      const accessToken = await getFcmAccessToken(FCM_SA_RAW);
      if (accessToken) {
        const goneFcm: string[] = [];
        for (const row of fcmTokens) {
          try {
            const resp = await fetch(
              `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT}/messages:send`,
              {
                method: 'POST',
                headers: {
                  Authorization: `Bearer ${accessToken}`,
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                  message: {
                    token: row.token,
                    notification: { title, body: body ?? '' },
                    data: { order_id: order_id ?? '', type: type ?? '' },
                    android: {
                      priority: 'high',
                      notification: { channel_id: 'dastak_orders' },
                    },
                  },
                }),
              }
            );
            if (resp.ok) {
              fcmSent++;
            } else {
              const err = await resp.json().catch(() => ({}));
              if (err?.error?.code === 404 || err?.error?.details?.some?.((d: any) => d.errorCode === 'UNREGISTERED')) {
                goneFcm.push(row.token);
              }
            }
          } catch { /* network error — skip */ }
        }
        if (goneFcm.length > 0) {
          await sb.from('fcm_tokens').delete().in('token', goneFcm);
        }
      }
    }
  }

  if (!subs || subs.length === 0) return json({ sent: fcmSent });
  if (!VAPID_PUBLIC || !VAPID_PRIVATE) return json({ sent: fcmSent, error: 'vapid_not_configured' }, { status: 503 });

  const { privateKey, pubRaw } = await importVapidKeys(VAPID_PUBLIC, VAPID_PRIVATE);
  const pushPayload = JSON.stringify({ title, body: body ?? '', order_id, type });

  let sent = 0;
  const gone: string[] = [];

  for (const sub of subs) {
    try {
      const r = await sendPushToEndpoint(sub.endpoint, sub.p256dh, sub.auth, pushPayload, privateKey, pubRaw, VAPID_SUBJECT);
      if (r.ok) {
        sent++;
      } else if (r.status === 404 || r.status === 410) {
        gone.push(sub.endpoint);
      }
    } catch { /* network error — skip */ }
  }

  if (gone.length > 0) {
    await sb.from('push_subscriptions').delete().in('endpoint', gone);
  }

  return json({ sent: sent + fcmSent, cleaned: gone.length });
});
