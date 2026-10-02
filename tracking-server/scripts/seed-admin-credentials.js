import 'dotenv/config';
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

const projectId = process.env.FIREBASE_PROJECT_ID
  ?? process.env.GOOGLE_CLOUD_PROJECT
  ?? process.env.GCLOUD_PROJECT
  ?? 'fixnow-a6515';

const adminPassword = process.env.FIXNOW_ADMIN_SEED_PASSWORD ?? 'fixnow';
const defaultPhone = process.env.FIXNOW_ADMIN_SEED_PHONE ?? '0000000000';

const cbeBranchDefaults = {
  id: process.env.FIXNOW_CBE_BRANCH_ID ?? 'coimbatore',
  name: process.env.FIXNOW_CBE_BRANCH_NAME ?? 'FixNow Coimbatore',
  city: 'Coimbatore',
  latitude: 11.0168,
  longitude: 76.9558,
  aliases: [
    'coimbatore',
    'cbe',
    'kovai',
    'peelamedu',
    'gandhipuram',
    'rs puram',
    'saibaba colony',
    'singanallur',
  ],
  radiusMeters: 65000,
  isActive: true,
};

if (adminPassword.length < 6) {
  throw new Error('FIXNOW_ADMIN_SEED_PASSWORD must contain at least 6 characters.');
}

if (getApps().length === 0) {
  initializeApp({
    credential: applicationDefault(),
    projectId,
  });
}

const auth = getAuth();
const firestore = getFirestore();

async function main() {
  const superAdmin = await upsertAuthUser({
    email: 'superadmin@gmail.com',
    password: adminPassword,
    displayName: 'superadmin',
  });
  await upsertUserProfile(superAdmin.uid, {
    name: 'superadmin',
    email: 'superadmin@gmail.com',
    phone: defaultPhone,
    role: 'superAdmin',
    accountStatus: 'approved',
    isActive: true,
  });

  const branch = await findOrCreateCbeBranch();
  const cbeAdmin = await upsertAuthUser({
    email: 'cbeadmin@gmail.com',
    password: adminPassword,
    displayName: 'cbeadmin',
  });
  await upsertUserProfile(cbeAdmin.uid, {
    name: 'cbeadmin',
    email: 'cbeadmin@gmail.com',
    phone: defaultPhone,
    role: 'branchAdmin',
    accountStatus: 'approved',
    isActive: true,
    branchId: branch.id,
    branchName: branch.name,
    createdBy: superAdmin.uid,
  });
  await firestore.collection('branches').doc(branch.id).set({
    branchAdminIds: FieldValue.arrayUnion(cbeAdmin.uid),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  await writeAudit({
    actorId: superAdmin.uid,
    action: 'adminCredentials.seeded',
    targetId: superAdmin.uid,
    targetType: 'user',
    summary: 'Seeded Super Admin superadmin@gmail.com',
  });
  await writeAudit({
    actorId: superAdmin.uid,
    action: 'adminCredentials.seeded',
    targetId: cbeAdmin.uid,
    targetType: 'branchAdmin',
    branchId: branch.id,
    summary: 'Seeded Branch Admin cbeadmin@gmail.com',
  });

  console.log('FixNow admin credentials are ready:');
  console.log(`- superadmin@gmail.com / ${adminPassword}`);
  console.log(`- cbeadmin@gmail.com / ${adminPassword} (${branch.name})`);
}

async function upsertAuthUser({ email, password, displayName }) {
  try {
    const existing = await auth.getUserByEmail(email);
    await auth.updateUser(existing.uid, {
      password,
      displayName,
      disabled: false,
    });
    return existing;
  } catch (error) {
    if (error?.code !== 'auth/user-not-found') throw error;
    return auth.createUser({
      email,
      password,
      displayName,
      disabled: false,
    });
  }
}

async function upsertUserProfile(uid, data) {
  const ref = firestore.collection('users').doc(uid);
  const snapshot = await ref.get();
  await ref.set({
    uid,
    ...data,
    createdAt: snapshot.exists
      ? snapshot.data()?.createdAt ?? FieldValue.serverTimestamp()
      : FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

async function findOrCreateCbeBranch() {
  const branches = await firestore.collection('branches').get();
  for (const doc of branches.docs) {
    const data = doc.data() ?? {};
    const terms = [
      doc.id,
      data.name,
      data.city,
      ...(Array.isArray(data.aliases) ? data.aliases : []),
    ].map(normalize).filter(Boolean);
    if (terms.some((term) => ['coimbatore', 'cbe', 'kovai'].includes(term))) {
      return {
        id: doc.id,
        name: data.name ?? 'FixNow Coimbatore',
      };
    }
  }

  await firestore.collection('branches').doc(cbeBranchDefaults.id).set({
    ...cbeBranchDefaults,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return {
    id: cbeBranchDefaults.id,
    name: cbeBranchDefaults.name,
  };
}

async function writeAudit({
  actorId,
  action,
  targetId,
  targetType,
  branchId,
  summary,
}) {
  await firestore.collection('audit_logs').add({
    actorId,
    actorRole: 'superAdmin',
    action,
    targetType,
    targetId,
    ...(branchId ? { branchId } : {}),
    summary,
    createdAt: FieldValue.serverTimestamp(),
  });
}

function normalize(value) {
  return String(value ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '');
}

main().catch((error) => {
  const message = String(error?.message ?? error);
  if (
    message.includes('Could not load the default credentials')
    || message.includes('Unable to detect a Project Id')
  ) {
    console.error(
      'Firebase Admin credentials are missing. Set FIREBASE_PROJECT_ID=fixnow-a6515 and GOOGLE_APPLICATION_CREDENTIALS to your Firebase service account JSON.',
    );
  } else {
    console.error(error);
  }
  process.exitCode = 1;
});
