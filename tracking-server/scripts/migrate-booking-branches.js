import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

import { planBookingBranchMigration } from '../src/booking-branch-migration.js';

if (getApps().length === 0) {
  initializeApp({ credential: applicationDefault() });
}

const db = getFirestore();
const apply = process.argv.includes('--apply');
const [branchesSnapshot, usersSnapshot, bookingsSnapshot] = await Promise.all([
  db.collection('branches').get(),
  db.collection('users').get(),
  db.collection('bookings').get(),
]);
const branches = branchesSnapshot.docs.map((doc) => ({
  id: doc.id,
  ...doc.data(),
}));
const users = new Map(
  usersSnapshot.docs.map((doc) => [doc.id, { id: doc.id, ...doc.data() }]),
);
const planned = [];
const blocked = [];

for (const doc of bookingsSnapshot.docs) {
  const booking = { id: doc.id, ...doc.data() };
  const plan = planBookingBranchMigration(booking, {
    branches,
    customer: users.get(booking.customerId),
    defaultBranchId: process.env.DEFAULT_BRANCH_ID,
  });
  if (!plan) continue;
  if (plan.blocked) {
    blocked.push({ bookingId: doc.id, ...plan });
  } else {
    planned.push({ ref: doc.ref, bookingId: doc.id, ...plan });
  }
}

console.log(JSON.stringify({
  mode: apply ? 'apply' : 'dry-run',
  planned: planned.map(({ ref: _, ...item }) => item),
  blocked,
}, null, 2));

if (!apply) {
  console.log('Dry run only. Resolve blocked bookings before using --apply.');
  process.exit(0);
}
if (blocked.length > 0) {
  throw new Error('Migration stopped: one or more bookings need a branch decision.');
}

for (let offset = 0; offset < planned.length; offset += 400) {
  const batch = db.batch();
  for (const change of planned.slice(offset, offset + 400)) {
    batch.update(change.ref, {
      branchId: change.branchId,
      branchName: change.branchName,
      branchMigratedAt: FieldValue.serverTimestamp(),
      branchMigrationSource: change.source,
    });
  }
  await batch.commit();
}
console.log(`Booking branch migration applied to ${planned.length} document(s).`);
