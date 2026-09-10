import test from 'node:test';
import assert from 'node:assert/strict';
import {
  anonymizedCustomerId,
  eraseCustomerAccount,
  registerAccountDeletionRoutes,
} from '../src/account-deletion.js';

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; },
  };
}

function fakeDocument(path, data = {}) {
  const id = path.split('/').at(-1);
  return { id, ref: { path, id }, data: () => data };
}

function deletionFixture() {
  const documents = {
    bookings: [fakeDocument('bookings/booking-1')],
    bills: [fakeDocument('bills/bill-1', { paymentApprovedBy: 'customer-1' })],
    reviews: [fakeDocument('reviews/review-1')],
    notifications: [fakeDocument('notifications/notification-1')],
    device_tokens: [fakeDocument('device_tokens/token-1')],
  };
  const mutations = [];
  const directSets = [];
  const firestore = {
    collection(name) {
      return {
        doc(id) {
          const ref = { path: `${name}/${id}` };
          return {
            ...ref,
            async set(data, options) { directSets.push({ ref, data, options }); },
          };
        },
        where(field, operator, value) {
          assert.equal(field === 'userId' || field === 'customerId', true);
          assert.equal(operator, '==');
          assert.equal(value, 'customer-1');
          return { async get() { return { docs: documents[name] ?? [] }; } };
        },
      };
    },
    batch() {
      const pending = [];
      return {
        set(ref, data, options) { pending.push({ type: 'set', ref, data, options }); },
        delete(ref) { pending.push({ type: 'delete', ref }); },
        async commit() { mutations.push(...pending); },
      };
    },
  };
  const authCalls = [];
  const auth = {
    async deleteUser(uid) { authCalls.push(uid); },
  };
  const storageCalls = [];
  const storage = {
    bucket() {
      return {
        async deleteFiles(options) { storageCalls.push(options); },
      };
    },
  };
  return { firestore, auth, storage, mutations, directSets, authCalls, storageCalls };
}

test('anonymous customer ID is deterministic and does not expose the UID', () => {
  const first = anonymizedCustomerId('customer-1');
  assert.equal(first, anonymizedCustomerId('customer-1'));
  assert.match(first, /^deleted_[a-f0-9]{20}$/);
  assert.equal(first.includes('customer-1'), false);
});

test('account deletion rejects staff accounts', async () => {
  const routes = new Map();
  registerAccountDeletionRoutes({
    post(path, handler) { routes.set(path, handler); },
  }, { auth: {}, firestore: {} });
  const res = responseRecorder();
  await routes.get('/api/account/deletion-request')(
    { principal: { uid: 'tech-1', role: 'technician' } },
    res,
  );
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.ok, false);
});

test('customer erasure removes identity and anonymizes retained records', async () => {
  const fixture = deletionFixture();
  const result = await eraseCustomerAccount({
    uid: 'customer-1',
    firestore: fixture.firestore,
    auth: fixture.auth,
    storage: fixture.storage,
  });
  const byPath = new Map(fixture.mutations.map((item) => [item.ref.path, item]));

  assert.equal(result.anonymizedBookings, 1);
  assert.equal(byPath.get('bookings/booking-1').data.customerName, 'Deleted customer');
  assert.equal(byPath.get('bookings/booking-1').data.phone, '');
  assert.equal(byPath.get('bills/bill-1').data.customerId, result.anonymousId);
  assert.equal(byPath.get('reviews/review-1').data.reviewerName, 'Deleted customer');
  assert.equal(byPath.get('notifications/notification-1').type, 'delete');
  assert.equal(byPath.get('device_tokens/token-1').type, 'delete');
  assert.equal(byPath.get('users/customer-1').type, 'delete');
  assert.equal(byPath.get('account_deletion_requests/customer-1').type, 'delete');
  assert.equal(
    byPath.get(`account_deletion_audit/${result.anonymousId}`).data.status,
    'completed',
  );
  assert.deepEqual(fixture.authCalls, ['customer-1']);
  assert.deepEqual(fixture.storageCalls, [
    { prefix: 'profile_photos/customer-1/', force: true },
    { prefix: 'bookings/booking-1/', force: true },
  ]);
  assert.equal(fixture.directSets[0].data.status, 'processing');
  const scrub = fixture.mutations.find(
    (item) => item.ref.path === 'users/customer-1' && item.type === 'set',
  );
  assert.equal(scrub.data.name, 'Deleted customer');
  assert.equal(scrub.data.isActive, false);
});
