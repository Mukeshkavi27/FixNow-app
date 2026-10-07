import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createFinalBill,
  validateFinalBillInput,
} from '../src/billing.js';

function snapshot(data) {
  return { exists: data != null, data: () => data };
}

function fixture({ booking, bill = null, technician = {} } = {}) {
  const writes = [];
  const notifications = [];
  const refs = new Map();
  const firestore = {
    collection(name) {
      return {
        doc(id) {
          const ref = { path: `${name}/${id}`, id };
          refs.set(ref.path, ref);
          return ref;
        },
        async add(data) { notifications.push(data); },
      };
    },
    async runTransaction(callback) {
      return callback({
        async get(ref) {
          if (ref.path === 'bookings/booking-1') return snapshot(booking);
          if (ref.path === 'bills/booking-1') return snapshot(bill);
          if (ref.path === 'users/tech-1') return snapshot(technician);
          return snapshot(null);
        },
        create(ref, data) { writes.push({ type: 'create', ref, data }); },
        update(ref, data) { writes.push({ type: 'update', ref, data }); },
      });
    },
  };
  return { firestore, writes, notifications };
}

const completeBooking = {
  technicianId: 'tech-1',
  customerId: 'customer-1',
  branchId: 'branch-1',
  status: 'serviceCompleted',
  technicianCompletedWorkAt: new Date(),
  customerConfirmedWorkCompletedAt: new Date(),
};

test('validates final bill amounts and preserves a short adjustment reason', () => {
  const input = validateFinalBillInput({
    bookingId: 'booking-1',
    labourCharge: '100',
    partsCharge: 55.5,
    adjustmentReason: 'Extra replacement part',
  });
  assert.deepEqual(input, {
    bookingId: 'booking-1',
    labourCharge: 100,
    partsCharge: 55.5,
    serviceAmount: 155.5,
    adjustmentReason: 'Extra replacement part',
  });
  assert.throws(() => validateFinalBillInput({
    bookingId: 'booking-1', labourCharge: -1, partsCharge: 0,
  }));
});

test('creates the bill and advances only a customer-confirmed technician job', async () => {
  const testFixture = fixture({
    booking: completeBooking,
    technician: { branchId: 'branch-1' },
  });
  const result = await createFinalBill({
    principal: { uid: 'tech-1', role: 'technician' },
    input: validateFinalBillInput({
      bookingId: 'booking-1', labourCharge: 100, partsCharge: 50,
    }),
    firestore: testFixture.firestore,
  });
  assert.equal(result.alreadyGenerated, false);
  assert.equal(testFixture.writes[0].type, 'create');
  assert.equal(testFixture.writes[0].data.amount, 177);
  assert.equal(testFixture.writes[0].data.revenueBranchId, 'branch-1');
  assert.deepEqual(testFixture.writes[1].data.status, 'billGenerated');
  assert.equal(testFixture.notifications.length, 1);
});

test('does not duplicate an existing final bill', async () => {
  const testFixture = fixture({
    booking: { ...completeBooking, status: 'billGenerated' },
    bill: { bookingId: 'booking-1' },
  });
  const result = await createFinalBill({
    principal: { uid: 'tech-1', role: 'technician' },
    input: validateFinalBillInput({
      bookingId: 'booking-1', labourCharge: 100, partsCharge: 50,
    }),
    firestore: testFixture.firestore,
  });
  assert.equal(result.alreadyGenerated, true);
  assert.equal(testFixture.writes.length, 0);
  assert.equal(testFixture.notifications.length, 0);
});
