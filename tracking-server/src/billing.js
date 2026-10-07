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
}
