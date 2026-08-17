import 'dotenv/config';
import { FieldValue } from 'firebase-admin/firestore';
import { firestore } from '../src/firebase-auth.js';

const apply = process.argv.includes('--apply');

const [
  bookings,
  bills,
  estimates,
  reviews,
  notifications,
  activeJobs,
  auditLogs,
  locations,
  locationHistory,
] = await Promise.all([
  firestore.collection('bookings').get(),
  firestore.collection('bills').get(),
  firestore.collection('estimates').get(),
  firestore.collection('reviews').get(),
  firestore.collection('notifications').get(),
  firestore.collection('technician_active_jobs').get(),
  firestore.collection('audit_logs').get(),
  firestore.collection('technician_locations').get(),
  firestore.collectionGroup('history').get(),
]);

const nonEmptyBookingId = (data) =>
  typeof data.bookingId === 'string' && data.bookingId.trim().length > 0;
const linked = (snapshot) => snapshot.docs.filter((doc) => nonEmptyBookingId(doc.data()));
const bookingReviews = linked(reviews);
const bookingNotifications = linked(notifications);
const bookingAuditLogs = linked(auditLogs);
const bookingRouteHistory = locationHistory.docs.filter((doc) =>
  typeof doc.data().activeBookingId === 'string' &&
  doc.data().activeBookingId.trim().length > 0,
);
const locationsToClear = locations.docs.filter((doc) =>
  typeof doc.data().activeBookingId === 'string' &&
  doc.data().activeBookingId.trim().length > 0,
);

const deletions = [
  ...bookings.docs,
  ...bills.docs,
  ...estimates.docs,
  ...bookingReviews,
  ...bookingNotifications,
  ...activeJobs.docs,
  ...bookingAuditLogs,
  ...bookingRouteHistory,
];

console.table([
  ['bookings', bookings.size],
  ['bills', bills.size],
  ['estimates', estimates.size],
  ['booking customer reviews', bookingReviews.length],
  ['booking notifications', bookingNotifications.length],
  ['active job locks', activeJobs.size],
  ['booking audit logs', bookingAuditLogs.length],
  ['booking route-history points', bookingRouteHistory.length],
  ['location records to unlink', locationsToClear.length],
].map(([target, count]) => ({ target, count })));
console.log('Preserved: users, branches, attendance, incentives, app config, and admin reviews.');

if (!apply) {
  console.log('Dry run only. Rerun with --apply to delete the listed booking data.');
  process.exit(0);
}

for (let index = 0; index < deletions.length; index += 400) {
  const batch = firestore.batch();
  for (const doc of deletions.slice(index, index + 400)) batch.delete(doc.ref);
  await batch.commit();
}
for (let index = 0; index < locationsToClear.length; index += 400) {
  const batch = firestore.batch();
  for (const doc of locationsToClear.slice(index, index + 400)) {
    batch.update(doc.ref, {
      activeBookingId: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}
console.log(`Deleted ${deletions.length} booking-linked document(s) and unlinked ${locationsToClear.length} location record(s).`);
