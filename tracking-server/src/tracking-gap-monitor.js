import { FieldValue } from 'firebase-admin/firestore';

export const trackingGapThresholdMs = 3 * 60 * 1000;

export function isTrackingGap(location, now = new Date()) {
  if (location?.isOnDuty !== true || location?.isOnline !== true) return false;
  const updatedAt = location.updatedAt?.toDate?.() ?? location.updatedAt;
  if (!(updatedAt instanceof Date) || Number.isNaN(updatedAt.getTime())) return true;
  return now.getTime() - updatedAt.getTime() >= trackingGapThresholdMs;
}

function incidentKey(technicianId, updatedAt) {
  const value = updatedAt?.toMillis?.()
    ?? updatedAt?.getTime?.()
    ?? 0;
  return `${technicianId}_${value}`;
}

function notificationData({ userId, recipientRole, technicianId, branchId,
  technicianName, type, title, body }) {
  return {
    userId,
    recipientRole,
    technicianId,
    branchId,
    type,
    title,
    body,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
  };
}

export async function runTrackingGapCheck(firestore, now = new Date()) {
  const [snapshot, activeStateSnapshot] = await Promise.all([
    firestore.collection('technician_locations')
      .where('isOnDuty', '==', true).get(),
    firestore.collection('tracking_gap_state')
      .where('active', '==', true).get(),
  ]);
  const activeStates = new Map(activeStateSnapshot.docs.map(
    (doc) => [doc.id, doc.data()],
  ));
  let opened = 0;
  let restored = 0;

  await Promise.all(snapshot.docs.map(async (locationDoc) => {
    const location = locationDoc.data();
    const technicianId = location.technicianId ?? locationDoc.id;
    const stateRef = firestore.collection('tracking_gap_state').doc(technicianId);
    const state = activeStates.get(technicianId) ?? {};
    const hasGap = isTrackingGap(location, now);

    if (!hasGap && state.active === true) {
      const technicianName = state.technicianName ?? 'Technician';
      const key = state.incidentKey ?? technicianId;
      const batch = firestore.batch();
      batch.set(stateRef, {
        active: false,
        restoredAt: FieldValue.serverTimestamp(),
        lastLocationAt: location.updatedAt ?? null,
      }, { merge: true });
      batch.set(
        firestore.collection('notifications').doc(`tracking_restored_${key}_branch`),
        notificationData({
          userId: `branch:${location.branchId}`,
          recipientRole: 'branchAdmin',
          technicianId,
          branchId: location.branchId ?? null,
          technicianName,
          type: 'trackingRestored',
          title: 'Technician tracking restored',
          body: `${technicianName}'s live GPS updates have resumed.`,
        }),
      );
      batch.set(
        firestore.collection('notifications').doc(`tracking_restored_${key}_super`),
        notificationData({
          userId: 'role:superAdmin',
          recipientRole: 'superAdmin',
          technicianId,
          branchId: location.branchId ?? null,
          technicianName,
          type: 'trackingRestored',
          title: 'Technician tracking restored',
          body: `${technicianName}'s live GPS updates have resumed.`,
        }),
      );
      await batch.commit();
      restored += 1;
      return;
    }
    if (!hasGap || state.active === true) return;

    const profile = await firestore.collection('users').doc(technicianId).get();
    const technicianName = profile.data()?.name?.trim() || 'Technician';
    const key = incidentKey(technicianId, location.updatedAt);
    const body = `${technicianName} has not sent a GPS update for at least 3 minutes. Check location permission, GPS, battery restrictions, phone restart or force-stop.`;
    const batch = firestore.batch();
    batch.set(stateRef, {
      active: true,
      incidentKey: key,
      technicianId,
      technicianName,
      branchId: location.branchId ?? null,
      gapStartedAt: location.updatedAt ?? null,
      alertedAt: FieldValue.serverTimestamp(),
    });
    batch.set(
      firestore.collection('notifications').doc(`tracking_gap_${key}_branch`),
      notificationData({
        userId: `branch:${location.branchId}`,
        recipientRole: 'branchAdmin',
        technicianId,
        branchId: location.branchId ?? null,
        technicianName,
        type: 'trackingGap',
        title: 'Technician tracking stopped',
        body,
      }),
    );
    batch.set(
      firestore.collection('notifications').doc(`tracking_gap_${key}_super`),
      notificationData({
        userId: 'role:superAdmin',
        recipientRole: 'superAdmin',
        technicianId,
        branchId: location.branchId ?? null,
        technicianName,
        type: 'trackingGap',
        title: 'Technician tracking stopped',
        body,
      }),
    );
    await batch.commit();
    opened += 1;
  }));
  return { checked: snapshot.size, opened, restored };
}

export function startTrackingGapMonitor(firestore, logger = console) {
  let running = false;
  const tick = async () => {
    if (running) return;
    running = true;
    try { await runTrackingGapCheck(firestore); }
    catch (error) { logger.error('Tracking gap monitor failed:', error); }
    finally { running = false; }
  };
  void tick();
  const timer = setInterval(tick, 60_000);
  return () => clearInterval(timer);
}
