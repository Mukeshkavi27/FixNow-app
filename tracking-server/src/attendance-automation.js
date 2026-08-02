import { FieldValue, Timestamp } from 'firebase-admin/firestore';

const istOffsetMinutes = 330;

export function attendanceActionAt(now = new Date()) {
  const ist = new Date(now.getTime() + istOffsetMinutes * 60_000);
  const minutes = ist.getUTCHours() * 60 + ist.getUTCMinutes();
  const dayKey = `${ist.getUTCFullYear()}-${String(ist.getUTCMonth() + 1).padStart(2, '0')}-${String(ist.getUTCDate()).padStart(2, '0')}`;
  if (minutes >= 585) return { action: 'absent', dayKey, slot: '09:45' };
  if (minutes < 540 || minutes > 580 || minutes % 10 !== 0) return { action: null, dayKey };
  return { action: 'reminder', dayKey, slot: `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}` };
}

export async function runAttendanceAutomation(
  firestore,
  now = new Date(),
  messaging = null,
) {
  const schedule = attendanceActionAt(now);
  if (!schedule.action) return { processed: 0 };
  const technicians = await firestore.collection('users')
    .where('role', '==', 'technician').where('isActive', '==', true).get();
  let processed = 0;
  await Promise.all(technicians.docs.map(async (technician) => {
    const data = technician.data();
    if (data.accountStatus !== 'approved') return;
    const attendanceId = `${technician.id}_${schedule.dayKey}`;
    const attendanceRef = firestore.collection('attendance').doc(attendanceId);
    const attendance = await attendanceRef.get();
    if (attendance.exists) return;
    if (schedule.action === 'reminder') {
      const notificationId =
        `attendance_reminder_${attendanceId}_${schedule.slot.replace(':', '')}`;
      await firestore.collection('notifications')
        .doc(notificationId).set({
          userId: technician.id,
          technicianId: technician.id,
          branchId: data.branchId ?? null,
          type: 'attendanceReminder',
          title: "Please mark today's attendance.",
          body: 'Attendance is mandatory.',
          isRead: false,
          scheduledSlot: schedule.slot,
          createdAt: FieldValue.serverTimestamp(),
        }, { merge: false });
      if (messaging) {
        try {
          const tokenSnapshot = await firestore.collection('device_tokens')
            .doc(technician.id).get();
          const token = tokenSnapshot.data()?.token;
          if (typeof token === 'string' && token.length > 0) {
            const messageId = await messaging.send({
              token,
              notification: {
                title: "Please mark today's attendance.",
                body: 'Attendance is mandatory.',
              },
              data: {
                type: 'attendanceReminder',
                notificationId,
                scheduledSlot: schedule.slot,
              },
              android: {
                priority: 'high',
                notification: { channelId: 'fixnow_technician_alerts' },
              },
            });
            await firestore.collection('notifications').doc(notificationId)
              .update({
                pushMessageId: messageId,
                pushSentAt: FieldValue.serverTimestamp(),
              });
          }
        } catch (error) {
          // A missing/expired token must not stop reminders or absence marking
          // for the rest of the technician fleet.
          await firestore.collection('notifications').doc(notificationId)
            .update({
              pushError: String(error?.code ?? error?.message ?? error),
              pushFailedAt: FieldValue.serverTimestamp(),
            }).catch(() => {});
        }
      }
    } else {
      await attendanceRef.create({
        technicianId: technician.id,
        branchId: data.branchId ?? null,
        selfieUrl: '', latitude: 0, longitude: 0,
        timestamp: Timestamp.fromDate(now), status: 'absent',
        absentReason: 'Not Marked', markedBy: 'system',
        faceMatchPassed: false, geofencePassed: false,
        locationSource: 'none', createdAt: FieldValue.serverTimestamp(),
      }).catch((error) => { if (error.code !== 6 && error.code !== 'already-exists') throw error; });
    }
    processed += 1;
  }));
  return { processed };
}

export function startAttendanceAutomation(
  firestore,
  logger = console,
  messaging = null,
) {
  let lastKey = '';
  const tick = async () => {
    const schedule = attendanceActionAt();
    const key = `${schedule.dayKey}|${schedule.action}|${schedule.slot ?? ''}`;
    if (!schedule.action || key === lastKey) return;
    lastKey = key;
    try { await runAttendanceAutomation(firestore, new Date(), messaging); }
    catch (error) { logger.error('Attendance automation failed:', error); }
  };
  void tick();
  const timer = setInterval(tick, 30_000);
  return () => clearInterval(timer);
}
