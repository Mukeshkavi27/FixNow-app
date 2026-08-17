import 'dotenv/config';
import { FieldValue } from 'firebase-admin/firestore';

import { firestore } from '../src/firebase-auth.js';

const apply = process.argv.includes('--apply');
const billsSnapshot = await firestore.collection('bills').get();
const planned = [];
const skipped = [];

for (const billDoc of billsSnapshot.docs) {
  const bill = billDoc.data();
  const hasTaxBreakdown = bill.serviceAmount != null
    && bill.cgstAmount != null
    && bill.sgstAmount != null;

  if (bill.isPaid === true || hasTaxBreakdown) continue;

  const bookingId = bill.bookingId ?? billDoc.id;
  const bookingDoc = await firestore.collection('bookings').doc(bookingId).get();
  if (!bookingDoc.exists || bookingDoc.data()?.status != 'billGenerated') {
    skipped.push({
      billId: billDoc.id,
      bookingId,
      reason: !bookingDoc.exists
        ? 'booking not found'
        : `booking status is ${bookingDoc.data()?.status ?? 'unknown'}`,
    });
    continue;
  }

  const serviceAmount = Number(bill.amount ?? 0);
  if (!Number.isFinite(serviceAmount) || serviceAmount <= 0) {
    skipped.push({ billId: billDoc.id, bookingId, reason: 'invalid bill amount' });
    continue;
  }
  const cgstAmount = Number((serviceAmount * 0.09).toFixed(2));
  const sgstAmount = Number((serviceAmount * 0.09).toFixed(2));
  const total = Number((serviceAmount + cgstAmount + sgstAmount).toFixed(2));
  planned.push({
    billRef: billDoc.ref,
    bookingId,
    billId: billDoc.id,
    customerId: bill.customerId,
    serviceAmount,
    cgstAmount,
    sgstAmount,
    total,
    hadUnfinalizedReceipt: Boolean(bill.paymentMode),
  });
}

console.log(JSON.stringify({
  mode: apply ? 'apply' : 'dry-run',
  billsToReissue: planned.map(({ billRef: _, ...bill }) => bill),
  skipped,
}, null, 2));

if (!apply) {
  console.log('Dry run only. Rerun with --apply after reviewing the result.');
  process.exit(0);
}

for (let offset = 0; offset < planned.length; offset += 400) {
  const batch = firestore.batch();
  for (const bill of planned.slice(offset, offset + 400)) {
    // Older unpaid invoices stored only their pre-tax amount. Their receipt
    // information is reset because the technician must confirm the revised
    // GST-inclusive total before the service can be closed.
    batch.update(bill.billRef, {
      amount: bill.total,
      serviceAmount: bill.serviceAmount,
      cgstAmount: bill.cgstAmount,
      sgstAmount: bill.sgstAmount,
      cgstRate: 9,
      sgstRate: 9,
      paymentMode: null,
      amountReceived: null,
      paymentProofUrl: null,
      paymentSubmittedAt: null,
      paymentConfirmedAt: null,
      paymentConfirmedBy: null,
      paymentApprovedAt: null,
      paymentApprovedBy: null,
      paidAt: null,
      updatedAt: FieldValue.serverTimestamp(),
      gstReissuedAt: FieldValue.serverTimestamp(),
    });
    batch.set(firestore.collection('notifications').doc(), {
      userId: bill.customerId,
      bookingId: bill.bookingId,
      type: 'billReissuedWithGst',
      title: 'Final bill updated',
      body: 'Your final bill has been updated to include CGST and SGST.',
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}

console.log(`Reissued ${planned.length} unpaid bill(s) with CGST and SGST.`);
