import assert from 'node:assert/strict';
import test from 'node:test';

import {
  closeOvertimeUpdate,
  isOvertimeTimestamp,
  overtimeClockParts,
  persistOvertimeUpdate,
} from '../src/overtime.js';

test('overtime is evaluated at 10 PM in the FixNow timezone', () => {
  assert.equal(isOvertimeTimestamp('2026-07-14T16:29:59.000Z'), false);
  assert.equal(isOvertimeTimestamp('2026-07-14T16:30:00.000Z'), true);
  assert.deepEqual(overtimeClockParts('2026-07-14T18:00:00.000Z'), {
    dateKey: '2026-07-14',
    hour: 23,
  });
});

test('first overtime update creates one session and three notifications', async () => {
  const writes = [];
  const reference = (path) => ({
    path,
    doc(id) {
      return reference(`${path}/${id}`);
    },
  });
  const firestore = {
    collection: (name) => reference(name),
    runTransaction: async (work) => work({
      get: async () => ({ exists: false }),
      set: (ref, data, options) => writes.push({ ref, data, options }),
    }),
  };
  const result = await persistOvertimeUpdate({
    technicianId: 'tech-1',
    adminBranchId: 'branch-1',
    jobId: 'booking-1',
  }, firestore, new Date('2026-07-14T16:45:00.000Z'));

  assert.equal(result.overtime, true);
  assert.equal(result.created, true);
  assert.equal(writes.length, 4);
  assert.equal(writes[0].ref.path, 'technician_overtime/tech-1_2026-07-14');
  assert.deepEqual(
    writes.slice(1).map((write) => write.data.recipientRole),
    ['technician', 'branchAdmin', 'superAdmin'],
  );
});

test('stopping tracking closes the active overtime session', async () => {
  const writes = [];
  const overtimeRef = {
    set: async (data, options) => writes.push({ data, options }),
  };
  const firestore = {
    collection: () => ({ doc: () => overtimeRef }),
  };
  const closed = await closeOvertimeUpdate({
    technicianId: 'tech-1',
    updatedAt: '2026-07-14T17:00:00.000Z',
  }, firestore);

  assert.equal(closed, true);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].data.isActive, false);
});
