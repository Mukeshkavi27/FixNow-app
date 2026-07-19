import { FieldValue } from 'firebase-admin/firestore';

const overtimeHour = 22;
const defaultTimeZone = 'Asia/Kolkata';

export function overtimeClockParts(
  timestamp,
  timeZone = defaultTimeZone,
) {
  const date = timestamp instanceof Date ? timestamp : new Date(timestamp);
  if (Number.isNaN(date.getTime())) throw new Error('Timestamp is invalid');
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);
  const value = Object.fromEntries(
    parts.filter((part) => part.type !== 'literal')
      .map((part) => [part.type, part.value]),
  );
  return {
    dateKey: `${value.year}-${value.month}-${value.day}`,
    hour: Number(value.hour),
  };
}

export function isOvertimeTimestamp(timestamp, timeZone = defaultTimeZone) {
  return overtimeClockParts(timestamp, timeZone).hour >= overtimeHour;
}

export async function persistOvertimeUpdate(
  update,
  firestore,
  receivedAt = new Date(),
) {
  const clock = overtimeClockParts(receivedAt);
  if (clock.hour < overtimeHour) return { overtime: false };
  const overtimeId = `${update.technicianId}_${clock.dateKey}`;
  const overtimeRef = firestore.collection('technician_overtime').doc(overtimeId);
  let created = false;
  await firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(overtimeRef);
    created = !existing.exists;
    transaction.set(overtimeRef, {
      technicianId: update.technicianId,
      branchId: update.adminBranchId,
      dateKey: clock.dateKey,
      ...(created ? { startedAt: FieldValue.serverTimestamp() } : {}),
      lastDetectedAt: FieldValue.serverTimestamp(),
      isActive: true,
      extraBookingIds: FieldValue.arrayUnion(update.jobId),
    }, { merge: true });
    if (created) {
      const base = {
        technicianId: update.technicianId,
        branchId: update.adminBranchId,
        dateKey: clock.dateKey,
        type: 'technicianOvertimeStarted',
        title: 'Working Overtime',
        isRead: false,
        createdAt: FieldValue.serverTimestamp(),
      };
      transaction.set(firestore.collection('notifications')
        .doc(`overtime_${update.technicianId}_${clock.dateKey}_technician`), {
        ...base,
        userId: update.technicianId,
        recipientRole: 'technician',
        body: 'Work after 10:00 PM is now being recorded as overtime.',
      });
      transaction.set(firestore.collection('notifications')
        .doc(`overtime_${update.technicianId}_${clock.dateKey}_branch`), {
        ...base,
        userId: `branch:${update.adminBranchId}`,
        recipientRole: 'branchAdmin',
        body: 'A branch technician started working after 10:00 PM.',
      });
      transaction.set(firestore.collection('notifications')
        .doc(`overtime_${update.technicianId}_${clock.dateKey}_super`), {
        ...base,
        userId: 'role:superAdmin',
        recipientRole: 'superAdmin',
        body: 'A technician started working after 10:00 PM.',
      });
    }
  });
  return { overtime: true, created, overtimeId };
}

export async function closeOvertimeUpdate(update, firestore) {
  if (!update?.updatedAt) return false;
  const clock = overtimeClockParts(update.updatedAt);
  if (clock.hour < overtimeHour) return false;
  await firestore.collection('technician_overtime')
    .doc(`${update.technicianId}_${clock.dateKey}`).set({
      isActive: false,
      lastDetectedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  return true;
}
