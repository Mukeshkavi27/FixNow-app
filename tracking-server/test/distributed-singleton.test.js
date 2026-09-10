import test from 'node:test';
import assert from 'node:assert/strict';
import { tryAcquireLease } from '../src/distributed-singleton.js';

function fakeFirestore(initial = null) {
  let data = initial;
  const ref = { path: 'service_leases/background-automation' };
  return {
    collection: () => ({ doc: () => ref }),
    runTransaction: async (work) => work({
      get: async () => ({ data: () => data }),
      set: (_ref, next) => { data = { ...data, ...next }; },
    }),
    data: () => data,
  };
}

test('lease permits one owner and supports takeover after expiry', async () => {
  const now = new Date('2026-09-10T08:00:00Z');
  const firestore = fakeFirestore();
  assert.equal(await tryAcquireLease({ firestore, leaseName: 'x', ownerId: 'a', now }), true);
  assert.equal(await tryAcquireLease({ firestore, leaseName: 'x', ownerId: 'b', now }), false);
  assert.equal(await tryAcquireLease({
    firestore,
    leaseName: 'x',
    ownerId: 'b',
    now: new Date(now.getTime() + 61_000),
  }), true);
  assert.equal(firestore.data().ownerId, 'b');
});
