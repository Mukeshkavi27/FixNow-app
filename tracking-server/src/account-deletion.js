import { createHash } from 'node:crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { roles } from './rbac.js';

const batchLimit = 400;

export function anonymizedCustomerId(uid) {
  const digest = createHash('sha256').update(`fixnow-deleted:${uid}`).digest('hex');
  return `deleted_${digest.slice(0, 20)}`;
}

async function matchingDocuments(firestore, collection, field, uid) {
  const snapshot = await firestore.collection(collection).where(field, '==', uid).get();
  return snapshot.docs;
}

async function commitMutations(firestore, mutations) {
  for (let offset = 0; offset < mutations.length; offset += batchLimit) {
    const batch = firestore.batch();
    for (const mutation of mutations.slice(offset, offset + batchLimit)) {
      if (mutation.type === 'delete') batch.delete(mutation.ref);
      else batch.set(mutation.ref, mutation.data, { merge: true });
    }
    await batch.commit();
  }
}

export async function eraseCustomerAccount({ uid, firestore, auth, storage }) {
  const anonymousId = anonymizedCustomerId(uid);
  const requestRef = firestore.collection('account_deletion_requests').doc(uid);
  const userRef = firestore.collection('users').doc(uid);

  await requestRef.set({
    userId: uid,
    role: roles.customer,
    status: 'processing',
    requestedAt: FieldValue.serverTimestamp(),
    source: 'androidApp',
  }, { merge: true });

  const [bookings, bills, reviews, notifications, tokens] = await Promise.all([
    matchingDocuments(firestore, 'bookings', 'customerId', uid),
    matchingDocuments(firestore, 'bills', 'customerId', uid),
    matchingDocuments(firestore, 'reviews', 'customerId', uid),
    matchingDocuments(firestore, 'notifications', 'userId', uid),
    matchingDocuments(firestore, 'device_tokens', 'userId', uid),
  ]);

  const remove = FieldValue.delete();
  const mutations = [
    {
      type: 'set',
      ref: userRef,
      data: {
        uid: anonymousId,
        name: 'Deleted customer',
        email: remove,
        phone: remove,
        phoneNormalized: remove,
        profilePhoto: remove,
        requestLatitude: remove,
        requestLongitude: remove,
        lastServiceAddress: remove,
        lastServiceLatitude: remove,
        lastServiceLongitude: remove,
        isActive: false,
        personalDataRemovedAt: FieldValue.serverTimestamp(),
      },
    },
    ...bookings.map((doc) => ({
      type: 'set',
      ref: doc.ref,
      data: {
        customerId: anonymousId,
        customerName: 'Deleted customer',
        phone: '',
        address: 'Removed after account deletion',
        problemDescription: 'Removed after account deletion',
        imageUrl: remove,
        servicePhotos: [],
        latitude: remove,
        longitude: remove,
        placeId: remove,
        pincode: remove,
        city: remove,
        stateName: remove,
        serviceArea: remove,
        landmark: remove,
        customerConfirmedLatitude: remove,
        customerConfirmedLongitude: remove,
        customerTechnicianDistanceMeters: remove,
        personalDataRemovedAt: FieldValue.serverTimestamp(),
      },
    })),
    ...bills.map((doc) => ({
      type: 'set',
      ref: doc.ref,
      data: {
        customerId: anonymousId,
        customerName: 'Deleted customer',
        serviceAddress: 'Removed after account deletion',
        paymentProofUrl: remove,
        ...(doc.data().paymentApprovedBy === uid
          ? { paymentApprovedBy: anonymousId }
          : {}),
        personalDataRemovedAt: FieldValue.serverTimestamp(),
      },
    })),
    ...reviews.map((doc) => ({
      type: 'set',
      ref: doc.ref,
      data: {
        customerId: anonymousId,
        reviewerId: anonymousId,
        reviewerName: 'Deleted customer',
        text: 'Review text removed after account deletion.',
        personalDataRemovedAt: FieldValue.serverTimestamp(),
      },
    })),
    ...notifications.map((doc) => ({ type: 'delete', ref: doc.ref })),
    ...tokens.map((doc) => ({ type: 'delete', ref: doc.ref })),
  ];

  await commitMutations(firestore, mutations);

  if (storage) {
    const bucket = storage.bucket();
    await Promise.all([
      bucket.deleteFiles({
        prefix: `profile_photos/${uid}/`,
        force: true,
      }),
      ...bookings.map((doc) => bucket.deleteFiles({
        prefix: `bookings/${doc.ref.id ?? doc.id}/`,
        force: true,
      })),
    ]);
  }

  await auth.deleteUser(uid);

  const completionBatch = firestore.batch();
  completionBatch.delete(userRef);
  completionBatch.delete(requestRef);
  completionBatch.set(
    firestore.collection('account_deletion_audit').doc(anonymousId),
    {
      anonymousId,
      status: 'completed',
      completedAt: FieldValue.serverTimestamp(),
      retainedBookingCount: bookings.length,
      retainedBillCount: bills.length,
      retainedReviewCount: reviews.length,
    },
  );
  await completionBatch.commit();

  return {
    anonymousId,
    anonymizedBookings: bookings.length,
    anonymizedBills: bills.length,
    anonymizedReviews: reviews.length,
    deletedNotifications: notifications.length,
    deletedTokens: tokens.length,
  };
}

export function registerAccountDeletionRoutes(app, { auth, firestore, storage }) {
  app.post('/api/account/deletion-request', async (req, res) => {
    const principal = req.principal;
    if (principal.role !== roles.customer) {
      res.status(403).json({
        ok: false,
        error: 'Only customer accounts can be deleted from the app. Staff accounts are managed by an administrator.',
      });
      return;
    }

    try {
      const result = await eraseCustomerAccount({
        uid: principal.uid,
        firestore,
        auth,
        storage,
      });
      res.json({ ok: true, status: 'completed', ...result });
    } catch (_) {
      res.status(500).json({
        ok: false,
        error: 'Account deletion could not be completed. Please retry or contact FixNow support.',
      });
    }
  });
}
