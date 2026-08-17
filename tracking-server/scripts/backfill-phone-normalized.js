import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { normalizeIndianMobile } from '../src/mobile-password-auth.js';

const projectId = process.env.FIREBASE_PROJECT_ID ?? 'fixnow-a6515';
if (getApps().length === 0) {
  initializeApp({ credential: applicationDefault(), projectId });
}

const apply = process.argv.includes('--apply');
const firestore = getFirestore();
const users = await firestore.collection('users').get();
const updates = [];
const skipped = [];

for (const user of users.docs) {
  try {
    const phoneNormalized = normalizeIndianMobile(user.data().phone);
    if (user.data().phoneNormalized !== phoneNormalized) {
      updates.push({ id: user.id, phoneNormalized });
    }
  } catch (_) {
    skipped.push(user.id);
  }
}

console.log(`Phone-login profiles to update: ${updates.length}`);
console.log(`Profiles skipped (invalid or missing mobile): ${skipped.length}`);
if (!apply) {
  console.log('Dry run only. Rerun with --apply after reviewing the result.');
  process.exit(0);
}

for (let index = 0; index < updates.length; index += 400) {
  const batch = firestore.batch();
  for (const update of updates.slice(index, index + 400)) {
    batch.update(firestore.collection('users').doc(update.id), {
      phoneNormalized: update.phoneNormalized,
    });
  }
  await batch.commit();
}
console.log(`Updated ${updates.length} profile(s).`);
