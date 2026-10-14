// Run with: node --test supabase/functions/place-order/routing.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { haversineKm, olaMetres, plausibleKm, roadDistance, type Point } from './routing.ts';

const store: Point = { lat: 28.8955, lng: 76.6066 };
const home: Point = { lat: 28.901, lng: 76.58 };
const straight = haversineKm(store, home);

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });
function fakeFetch(handlers: { google?: () => Response; ola?: () => Response }) {
  const calls: string[] = [];
  const fn = async (url: string) => {
    if (url.includes('routes.googleapis.com')) {
      calls.push('google');
      if (!handlers.google) throw new Error('unexpected');
      return handlers.google();
    }
    if (url.includes('api.olamaps.io')) {
      calls.push('ola');
      if (!handlers.ola) throw new Error('unexpected');
      return handlers.ola();
    }
    throw new Error(`unexpected url ${url}`);
  };
  return { fn, calls };
}

test('straight line between two Rohtak points is about 2.6 km', () => {
  assert.ok(straight > 2.4 && straight < 2.9, String(straight));
});

test('Ola response formats: summed legs, route total, and {value} objects', () => {
  assert.equal(olaMetres({ routes: [{ legs: [{ distance: 1200 }, { distance: 1800 }] }] }), 3000);
  assert.equal(olaMetres({ routes: [{ distance: 3100 }] }), 3100);
  assert.equal(olaMetres({ routes: [{ legs: [{ distance: { value: 2900, text: '2.9 km' } }] }] }), 2900);
  assert.equal(olaMetres({ routes: [] }), null);
  assert.equal(olaMetres({ routes: [{ legs: [{ distance: 'abc' }] }] }), null);
});

test('implausible distances are rejected', () => {
  assert.equal(plausibleKm(straight * 1.3, straight), true);
  assert.equal(plausibleKm(straight * 0.5, straight), false);
  assert.equal(plausibleKm(straight * 1000, straight), false);
  assert.equal(plausibleKm(Number.NaN, straight), false);
});

test('Google is used first when it answers sensibly', async () => {
  const f = fakeFetch({ google: () => json({ routes: [{ distanceMeters: 3200 }] }) });
  assert.deepEqual(await roadDistance(store, home, { googleKey: 'g', olaKey: 'o', fetchFn: f.fn }), { km: 3.2, provider: 'google' });
  assert.deepEqual(f.calls, ['google']);
});

test('Ola is used when Google is refused (e.g. billing closed)', async () => {
  const f = fakeFetch({ google: () => json({ error: { status: 'PERMISSION_DENIED' } }, 403), ola: () => json({ routes: [{ legs: [{ distance: 3350 }] }] }) });
  assert.deepEqual(await roadDistance(store, home, { googleKey: 'g', olaKey: 'o', fetchFn: f.fn }), { km: 3.35, provider: 'ola' });
  assert.deepEqual(f.calls, ['google', 'ola']);
});

test('an Ola answer in the wrong units falls back to the estimate', async () => {
  const f = fakeFetch({ ola: () => json({ routes: [{ legs: [{ distance: 3.35 }] }] }) });
  const d = await roadDistance(store, home, { olaKey: 'o', fetchFn: f.fn });
  assert.equal(d.provider, 'haversine');
  assert.ok(Math.abs(d.km - straight * 1.3) < 1e-9);
});

test('network errors and timeouts never block an order', async () => {
  const f = fakeFetch({
    google: () => {
      throw new Error('timeout');
    },
    ola: () => json({ message: 'Unauthorized' }, 401),
  });
  const d = await roadDistance(store, home, { googleKey: 'g', olaKey: 'o', fetchFn: f.fn });
  assert.equal(d.provider, 'haversine');
});

test('without any key no provider is called', async () => {
  const f = fakeFetch({});
  assert.equal((await roadDistance(store, home, { fetchFn: f.fn })).provider, 'haversine');
  assert.deepEqual(f.calls, []);
});
