import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

import { planReviewBranchMigration } from '../src/review-branch-migration.js';

if (getApps().length === 0) {
  initializeApp({ credential: applicationDefault() });
}

const db = getFirestore();
const apply = process.argv.includes('--apply');
const reviewsSnapshot = await db.collection('reviews').get();
const planned = [];
const blocked = [];

for (const doc of reviewsSnapshot.docs) {
  const review = { id: doc.id, ...doc.data() };
  const bookingDoc = await db.collection('bookings').doc(review.bookingId).get();
  const plan = planReviewBranchMigration(review, {
    booking: bookingDoc.exists ? bookingDoc.data() : null,
  });
  if (!plan) continue;
  if (plan.blocked) {
    blocked.push({ reviewId: doc.id, ...plan });
  } else {
    planned.push({ ref: doc.ref, reviewId: doc.id, ...plan });
  }
}

console.log(JSON.stringify({
  mode: apply ? 'apply' : 'dry-run',
  planned: planned.map(({ ref: _, ...item }) => item),
  blocked,
}, null, 2));

if (!apply) {
  console.log('Dry run only. Resolve blocked reviews before using --apply.');
  process.exit(0);
}
if (blocked.length > 0) {
  throw new Error('Migration stopped: review relationships need attention.');
}

for (let offset = 0; offset < planned.length; offset += 400) {
  const batch = db.batch();
  for (const change of planned.slice(offset, offset + 400)) {
    batch.update(change.ref, {
      branchId: change.branchId,
      branchMigratedAt: FieldValue.serverTimestamp(),
      branchMigrationSource: change.source,
    });
  }
  await batch.commit();
}
console.log(`Review branch migration applied to ${planned.length} document(s).`);
