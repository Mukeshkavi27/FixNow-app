import test from 'node:test';
import assert from 'node:assert/strict';

import {
  normalizeGpsPayload,
  persistGpsUpdate,
} from '../src/tracking-persistence.js';

test('GPS payload retains complete technician and booking telemetry', () => {
  const update = normalizeGpsPayload({
    technicianId: 'tech-1',
    jobId: 'booking-1',
    customerId: 'customer-1',
    adminBranchId: 'branch-a',
    latitude: 13.0827,
    longitude: 80.2707,
    speed: 8.2,
    accuracy: 4.5,
    timestamp: '2026-07-14T09:30:00.000Z',
  });

  assert.equal(update.technicianId, 'tech-1');
  assert.equal(update.jobId, 'booking-1');
  assert.equal(update.speed, 8.2);
  assert.equal(update.accuracy, 4.5);
  assert.equal(update.updatedAt, '2026-07-14T09:30:00.000Z');
  assert.throws(
    () => normalizeGpsPayload({
      technicianId: 'tech-1', jobId: 'booking-1', latitude: 100, longitude: 80,
    }),
    /Latitude is invalid/,
  );
});

test('GPS persistence updates latest point and appends immutable history', async () => {
  const writes = [];
  let committed = false;
  const historyRef = { path: 'technician_locations/tech-1/history/point-1' };
  const technicianRef = {
    path: 'technician_locations/tech-1',
    collection(name) {
      assert.equal(name, 'history');
      return { doc: () => historyRef };
    },
  };
  const firestore = {
    collection(name) {
      assert.equal(name, 'technician_locations');
      return { doc: () => technicianRef };
    },
    batch() {
      return {
        set(ref, data, options) { writes.push({ ref, data, options }); },
        async commit() { committed = true; },
      };
    },
  };
  const update = normalizeGpsPayload({
    technicianId: 'tech-1',
    jobId: 'booking-1',
    adminBranchId: 'branch-a',
    latitude: 13.0827,
    longitude: 80.2707,
    speed: 7,
    accuracy: 5,
    timestamp: '2026-07-14T09:30:00.000Z',
  });

  await persistGpsUpdate(update, firestore);

  assert.equal(committed, true);
  assert.equal(writes.length, 2);
  assert.equal(writes[0].ref.path, 'technician_locations/tech-1');
  assert.deepEqual(writes[0].options, { merge: true });
  assert.equal(
    writes[1].ref.path,
    'technician_locations/tech-1/history/point-1',
  );
  assert.equal(writes[1].data.activeBookingId, 'booking-1');
  assert.equal(writes[1].data.branchId, 'branch-a');
});

test('GPS replay history is limited to one point per technician per minute', async () => {
  const writes = [];
  const technicianRef = {
    path: 'technician_locations/tech-minute',
    collection() {
      return { doc: () => ({ path: 'technician_locations/tech-minute/history/point' }) };
    },
  };
  const firestore = {
    collection() { return { doc: () => technicianRef }; },
    batch() {
      return {
        set(ref, data, options) { writes.push({ ref, data, options }); },
        async commit() {},
      };
    },
  };
  const update = normalizeGpsPayload({
    technicianId: 'tech-minute', jobId: 'booking-1',
    latitude: 13.0827, longitude: 80.2707,
  });

  await persistGpsUpdate(update, firestore);
  await persistGpsUpdate(update, firestore);

  assert.equal(
    writes.filter((write) => write.ref.path.includes('/history/')).length,
    1,
  );
  assert.equal(
    writes.filter((write) => write.ref.path === 'technician_locations/tech-minute').length,
    2,
  );
});
