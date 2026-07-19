import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { planUserRoleMigration } from '../src/rbac-migration.js';

if (getApps().length === 0) {
  initializeApp({ credential: applicationDefault() });
}

const db = getFirestore();
const apply = process.argv.includes('--apply');
const superAdminUids = new Set(
  String(process.env.SUPER_ADMIN_UIDS ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean),
);
const options = {
  superAdminUids,
  defaultBranchId: process.env.DEFAULT_BRANCH_ID,
  defaultBranchName: process.env.DEFAULT_BRANCH_NAME,
};

const users = await db.collection('users').get();
const userChanges = [];
const blocked = [];
const userById = new Map(users.docs.map((doc) => [doc.id, doc.data()]));
for (const doc of users.docs) {
  const plan = planUserRoleMigration({ uid: doc.id, ...doc.data() }, options);
  if (!plan) continue;
  if (plan.blocked) {
    blocked.push({ uid: doc.id, ...plan });
  } else {
    userChanges.push({ ref: doc.ref, uid: doc.id, data: plan });
  }
}

const bookings = await db.collection('bookings').get();
const bookingById = new Map(bookings.docs.map((doc) => [doc.id, doc.data()]));
const branchBackfills = [];

for (const collection of ['bills', 'attendance', 'technician_locations']) {
  const snapshot = await db.collection(collection).get();
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (data.branchId) continue;
    const branchId = collection === 'bills'
      ? bookingById.get(data.bookingId ?? doc.id)?.branchId
      : userById.get(data.technicianId ?? doc.id)?.branchId;
    if (!branchId) {
      blocked.push({
        collection,
        id: doc.id,
        blocked: true,
        reason: 'Cannot derive branchId without changing relationships',
      });
      continue;
    }
    branchBackfills.push({ ref: doc.ref, collection, id: doc.id, data: { branchId } });
  }
}

const changes = [...userChanges, ...branchBackfills];

console.log(JSON.stringify({
  mode: apply ? 'apply' : 'dry-run',
  legacyAdmins: userChanges.length
    + blocked.filter((item) => item.uid).length,
  plannedUserChanges: userChanges.map(({ uid, data }) => ({ uid, ...data })),
  plannedBranchBackfills: branchBackfills.map(
    ({ collection, id, data }) => ({ collection, id, ...data }),
  ),
  blocked,
}, null, 2));

if (!apply) {
  console.log('Dry run only. Re-run with --apply after resolving every blocked account.');
  process.exit(0);
}
if (blocked.length > 0) {
  throw new Error('Migration stopped: assign a branch or set DEFAULT_BRANCH_ID.');
}

for (let offset = 0; offset < changes.length; offset += 400) {
  const batch = db.batch();
  for (const change of changes.slice(offset, offset + 400)) {
    batch.update(change.ref, {
      ...change.data,
      rbacMigratedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}
console.log(`RBAC migration applied to ${changes.length} user document(s).`);
