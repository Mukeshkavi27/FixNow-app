import test from 'node:test';
import assert from 'node:assert/strict';
import {
  isTrackingGap,
  runTrackingGapCheck,
  trackingGapThresholdMs,
} from '../src/tracking-gap-monitor.js';

function timestamp(date) {
  return {
    toDate: () => date,
    toMillis: () => date.getTime(),
  };
}

test('tracking gap starts after three missed one-minute updates', () => {
  const now = new Date('2026-08-29T10:10:00Z');
  assert.equal(isTrackingGap({
    isOnDuty: true,
    isOnline: true,
    updatedAt: timestamp(new Date(now.getTime() - trackingGapThresholdMs)),
  }, now), true);
  assert.equal(isTrackingGap({
    isOnDuty: true,
    isOnline: true,
    updatedAt: timestamp(new Date(now.getTime() - 60_000)),
  }, now), false);
  assert.equal(isTrackingGap({
    isOnDuty: false,
    isOnline: true,
    updatedAt: timestamp(new Date(0)),
  }, now), false);
});

test('gap monitor alerts branch and super admins once per incident', async () => {
  const now = new Date('2026-08-29T10:10:00Z');
  const oldUpdate = timestamp(new Date(now.getTime() - 4 * 60_000));
  const writes = [];
  const state = {};
  const refs = (path) => ({ path });
  const firestore = {
    collection(name) {
      return {
        where() {
          return {
            async get() {
              if (name === 'technician_locations') return {
                    size: 1,
                    docs: [{
                      id: 'tech-1',
                      data: () => ({
                        technicianId: 'tech-1',
                        branchId: 'branch-1',
                        isOnDuty: true,
                        isOnline: true,
                        updatedAt: oldUpdate,
                      }),
                    }],
                  };
              if (name === 'tracking_gap_state' && state['tech-1']) {
                return {
                  size: 1,
                  docs: [{ id: 'tech-1', data: () => state['tech-1'] }],
                };
              }
              return { size: 0, docs: [] };
            },
          };
        },
        doc(id) {
          const ref = refs(`${name}/${id}`);
          return {
            ...ref,
            async get() {
              if (name === 'users') {
                return { data: () => ({ name: 'Darshan' }) };
              }
              return { data: () => state[id] };
            },
          };
        },
      };
    },
    batch() {
      const pending = [];
      return {
        set(ref, data, options) { pending.push({ ref, data, options }); },
        async commit() {
          writes.push(...pending);
          for (const item of pending) {
            if (item.ref.path === 'tracking_gap_state/tech-1') {
              state['tech-1'] = item.data;
            }
          }
        },
      };
    },
  };

  const first = await runTrackingGapCheck(firestore, now);
  const second = await runTrackingGapCheck(firestore, now);
  assert.deepEqual(first, { checked: 1, opened: 1, restored: 0 });
  assert.deepEqual(second, { checked: 1, opened: 0, restored: 0 });
  const notifications = writes.filter((item) =>
    item.ref.path.startsWith('notifications/'));
  assert.equal(notifications.length, 2);
  assert.deepEqual(
    notifications.map((item) => item.data.userId).sort(),
    ['branch:branch-1', 'role:superAdmin'],
  );
  assert.equal(notifications[0].data.type, 'trackingGap');
});
