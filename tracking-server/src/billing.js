import { FieldValue } from 'firebase-admin/firestore';
import { roles } from './rbac.js';

function currency(value, label) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) {
    throw new Error(`${label} must be a valid non-negative amount`);
  }
  return Number(number.toFixed(2));
}

export function validateFinalBillInput(body) {
  const bookingId = String(body?.bookingId ?? '').trim();
  if (!bookingId) throw new Error('Booking ID is required');

  const labourCharge = currency(body?.labourCharge, 'Labour charge');
  const partsCharge = currency(body?.partsCharge, 'Parts charge');
  const serviceAmount = Number((labourCharge + partsCharge).toFixed(2));
  if (serviceAmount <= 0) throw new Error('Bill amount must be positive');

  const adjustmentReason = String(body?.adjustmentReason ?? '').trim();
  if (adjustmentReason.length > 500) {
    throw new Error('The reason for the charge change is too long');
  }

  return {
    bookingId,
    labourCharge,
    partsCharge,
    serviceAmount,
    adjustmentReason: adjustmentReason || null,
  };
}

export async function createFinalBill({ principal, input, firestore }) {
  if (principal?.role !== roles.technician) {
    const error = new Error('Only the assigned technician can generate this bill');
    error.statusCode = 403;
    throw error;
  }

  const bookingRef = firestore.collection('bookings').doc(input.bookingId);
  const billRef = firestore.collection('bills').doc(input.bookingId);
  const technicianRef = firestore.collection('users').doc(principal.uid);
  const result = await firestore.runTransaction(async (transaction) => {
    const [bookingSnapshot, billSnapshot, technicianSnapshot] = await Promise.all([
      transaction.get(bookingRef),
      transaction.get(billRef),
      transaction.get(technicianRef),
    ]);
    if (!bookingSnapshot.exists) throw new Error('Booking not found');
    const booking = bookingSnapshot.data();

    if (booking.technicianId !== principal.uid) {
      const error = new Error('This booking is not assigned to your account');
      error.statusCode = 403;
      throw error;
    }
    if (booking.status === 'billGenerated' && billSnapshot.exists) {
      return { alreadyGenerated: true, customerId: booking.customerId };
    }
    if (booking.status !== 'serviceCompleted') {
      throw new Error('The customer must confirm the completed work before billing');
    }
    if (!booking.technicianCompletedWorkAt) {
      throw new Error('Mark the work completed before generating a final bill');
    }
    if (!booking.customerConfirmedWorkCompletedAt) {
      throw new Error('The customer must confirm the completed work before billing');
    }
    if (billSnapshot.exists) {
      throw new Error('A final bill already exists for this booking. Refresh the job and try again');
    }

    const technician = technicianSnapshot.exists ? technicianSnapshot.data() : null;
    const revenueBranchId = technician?.nativeBranchId
      ?? technician?.branchId
      ?? booking.branchId;
    const cgstAmount = Number((input.serviceAmount * 0.09).toFixed(2));
    const sgstAmount = Number((input.serviceAmount * 0.09).toFixed(2));
    const payableAmount = Number((input.serviceAmount + cgstAmount + sgstAmount).toFixed(2));

    transaction.create(billRef, {
      bookingId: input.bookingId,
      customerId: booking.customerId,
      technicianId: principal.uid,
      branchId: booking.branchId,
      revenueBranchId,
      amount: payableAmount,
      serviceAmount: input.serviceAmount,
      labourCharge: input.labourCharge,
      partsCharge: input.partsCharge,
      adjustmentReason: input.adjustmentReason,
      cgstAmount,
      sgstAmount,
      cgstRate: 9,
      sgstRate: 9,
      applianceType: booking.applianceType ?? null,
      customerName: booking.customerName ?? null,
      technicianName: booking.technicianName ?? null,
      serviceAddress: booking.address ?? null,
      preferredTime: booking.preferredTime ?? null,
      technicianCompletedWorkAt: booking.technicianCompletedWorkAt,
      customerConfirmedWorkCompletedAt: booking.customerConfirmedWorkCompletedAt,
      createdAt: FieldValue.serverTimestamp(),
      isPaid: false,
      paymentMode: null,
      amountReceived: null,
      paymentProofUrl: null,
      paymentSubmittedAt: null,
      paymentConfirmedAt: null,
      paymentConfirmedBy: null,
      paymentApprovedAt: null,
      paymentApprovedBy: null,
    });
    transaction.update(bookingRef, {
      status: 'billGenerated',
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { alreadyGenerated: false, customerId: booking.customerId };
  });

  if (!result.alreadyGenerated) {
    await firestore.collection('notifications').add({
      userId: result.customerId,
      bookingId: input.bookingId,
      type: 'billGenerated',
      title: 'Final bill generated',
      body: 'Your final service bill is ready.',
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
    }).catch(() => {});
  }
  return result;
}

function bookingIdFrom(body) {
  const bookingId = String(body?.bookingId ?? '').trim();
  if (!bookingId) throw new Error('Booking ID is required');
  return bookingId;
}

async function notify(firestore, data) {
  await firestore.collection('notifications').add({
    ...data,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
  }).catch(() => {});
}

export async function requestWorkCompletion({ principal, bookingId, firestore }) {
  if (principal?.role !== roles.technician) {
    const error = new Error('Only the assigned technician can complete this step');
    error.statusCode = 403;
    throw error;
  }
  const bookingRef = firestore.collection('bookings').doc(bookingId);
  const customerId = await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists) throw new Error('Booking not found');
    const booking = snapshot.data();
    if (booking.technicianId !== principal.uid) {
      const error = new Error('This booking is not assigned to your account');
      error.statusCode = 403;
      throw error;
    }
    if (!['serviceStarted', 'serviceCompleted'].includes(booking.status)) {
      throw new Error('Work completion cannot be requested at this stage');
    }
    transaction.update(bookingRef, {
      status: 'workCompletedPendingCustomer',
      technicianCompletedWorkAt: FieldValue.serverTimestamp(),
      customerReportedWorkNotDoneAt: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return booking.customerId;
  });
  await notify(firestore, {
    userId: customerId,
    bookingId,
    type: 'technicianWorkCompleted',
    title: 'Confirm completed work',
    body: 'Your technician marked the service work as completed. Please confirm it before final billing.',
  });
}

export async function confirmWorkCompletion({ principal, bookingId, firestore }) {
  if (principal?.role !== roles.customer) {
    const error = new Error('Only the booking customer can confirm this work');
    error.statusCode = 403;
    throw error;
  }
  const bookingRef = firestore.collection('bookings').doc(bookingId);
  const technicianId = await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists) throw new Error('Booking not found');
    const booking = snapshot.data();
    if (booking.customerId !== principal.uid) {
      const error = new Error('You can only confirm your own booking');
      error.statusCode = 403;
      throw error;
    }
    if (booking.status === 'serviceCompleted' && booking.customerConfirmedWorkCompletedAt) {
      return booking.technicianId;
    }
    if (booking.status !== 'workCompletedPendingCustomer') {
      throw new Error('Work completion is not ready for confirmation');
    }
    transaction.update(bookingRef, {
      status: 'serviceCompleted',
      customerConfirmedWorkCompletedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (booking.technicianId) {
      transaction.delete(firestore.collection('technician_active_jobs').doc(booking.technicianId));
    }
    return booking.technicianId;
  });
  if (technicianId) {
    await notify(firestore, {
      userId: technicianId,
      bookingId,
      type: 'customerWorkCompletedConfirmed',
      title: 'Customer confirmed completion',
      body: 'The customer confirmed the work is completed. You can generate the final bill now.',
    });
  }
}

export async function recordCollectedPayment({ principal, body, firestore }) {
  if (principal?.role !== roles.technician) {
    const error = new Error('Only the assigned technician can record payment');
    error.statusCode = 403;
    throw error;
  }
  const bookingId = bookingIdFrom(body);
  const paymentMode = String(body?.paymentMode ?? '').trim();
  const amountReceived = currency(body?.amountReceived, 'Received amount');
  const paymentProofUrl = String(body?.paymentProofUrl ?? '').trim() || null;
  if (!['cash', 'upi', 'card', 'bankTransfer', 'other'].includes(paymentMode)) {
    throw new Error('Select a valid payment mode');
  }
  if (paymentMode !== 'cash' && !paymentProofUrl) {
    throw new Error('Upload payment proof for online payment');
  }
  const billRef = firestore.collection('bills').doc(bookingId);
  const bookingRef = firestore.collection('bookings').doc(bookingId);
  const customerId = await firestore.runTransaction(async (transaction) => {
    const [billSnapshot, bookingSnapshot] = await Promise.all([
      transaction.get(billRef), transaction.get(bookingRef),
    ]);
    if (!billSnapshot.exists || !bookingSnapshot.exists) throw new Error('Bill or booking not found');
    const bill = billSnapshot.data();
    if (bill.technicianId !== principal.uid) {
      const error = new Error('This bill is assigned to another technician');
      error.statusCode = 403;
      throw error;
    }
    if (bill.isPaid) throw new Error('This payment is already approved');
    if (bookingSnapshot.data().status !== 'billGenerated') {
      throw new Error('Payment can only be confirmed after final billing');
    }
    if (Number(bill.amount) !== amountReceived) {
      throw new Error('Received amount must match the final bill amount');
    }
    transaction.update(billRef, {
      isPaid: false, paymentMode, amountReceived, paymentProofUrl,
      paymentSubmittedAt: FieldValue.serverTimestamp(),
      paymentConfirmedAt: FieldValue.serverTimestamp(),
      paymentConfirmedBy: principal.uid, updatedAt: FieldValue.serverTimestamp(),
    });
    return bill.customerId;
  });
  await notify(firestore, {
    userId: customerId, bookingId, type: 'paymentSubmitted',
    title: 'Confirm payment received',
    body: 'Your technician recorded the payment. Please verify the amount and confirm to complete the service.',
  });
}

export async function approveCollectedPayment({ principal, bookingId, firestore }) {
  if (principal?.role !== roles.customer) {
    const error = new Error('Only the booking customer can approve payment');
    error.statusCode = 403;
    throw error;
  }
  const billRef = firestore.collection('bills').doc(bookingId);
  const bookingRef = firestore.collection('bookings').doc(bookingId);
  await firestore.runTransaction(async (transaction) => {
    const [billSnapshot, bookingSnapshot] = await Promise.all([
      transaction.get(billRef), transaction.get(bookingRef),
    ]);
    if (!billSnapshot.exists || !bookingSnapshot.exists) throw new Error('Bill or booking not found');
    const bill = billSnapshot.data();
    if (bill.customerId !== principal.uid) {
      const error = new Error('You can only confirm your own payment');
      error.statusCode = 403;
      throw error;
    }
    if (bill.isPaid) return;
    if (!bill.paymentMode || Number(bill.amountReceived) !== Number(bill.amount)) {
      throw new Error('The recorded payment is not ready for confirmation');
    }
    transaction.update(billRef, {
      isPaid: true, paidAt: FieldValue.serverTimestamp(),
      paymentApprovedAt: FieldValue.serverTimestamp(), paymentApprovedBy: principal.uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(bookingRef, {
      status: 'closed', updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

export function registerBillingRoutes(app, { firestore }) {
  app.post('/api/technician/bills', async (req, res) => {
    try {
      const input = validateFinalBillInput(req.body);
      const result = await createFinalBill({
        principal: req.principal,
        input,
        firestore,
      });
      res.status(result.alreadyGenerated ? 200 : 201).json({ ok: true, ...result });
    } catch (error) {
      const message = error?.message || 'Final bill could not be generated';
      const statusCode = error?.statusCode
        ?? (message.includes('already exists') ? 409 : 400);
      res.status(statusCode).json({ ok: false, error: message });
    }
  });
  app.post('/api/technician/work-completion', async (req, res) => {
    try {
      await requestWorkCompletion({ principal: req.principal, bookingId: bookingIdFrom(req.body), firestore });
      res.json({ ok: true });
    } catch (error) {
      res.status(error?.statusCode ?? 400).json({ ok: false, error: error?.message ?? 'Unable to request work completion' });
    }
  });
  app.post('/api/customer/work-completion', async (req, res) => {
    try {
      await confirmWorkCompletion({ principal: req.principal, bookingId: bookingIdFrom(req.body), firestore });
      res.json({ ok: true });
    } catch (error) {
      res.status(error?.statusCode ?? 400).json({ ok: false, error: error?.message ?? 'Unable to confirm work completion' });
    }
  });
  app.post('/api/technician/payments', async (req, res) => {
    try {
      await recordCollectedPayment({ principal: req.principal, body: req.body, firestore });
      res.json({ ok: true });
    } catch (error) {
      res.status(error?.statusCode ?? 400).json({ ok: false, error: error?.message ?? 'Unable to record payment' });
    }
  });
  app.post('/api/customer/payments/approve', async (req, res) => {
    try {
      await approveCollectedPayment({ principal: req.principal, bookingId: bookingIdFrom(req.body), firestore });
      res.json({ ok: true });
    } catch (error) {
      res.status(error?.statusCode ?? 400).json({ ok: false, error: error?.message ?? 'Unable to confirm payment' });
    }
  });
}
