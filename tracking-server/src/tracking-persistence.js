import { FieldValue } from 'firebase-admin/firestore';

// Live map telemetry can arrive every few seconds. Keep the current location
// fresh, but retain one immutable replay point per technician per minute.
const lastHistoryWriteAtByTechnician = new Map();
const historyIntervalMs = 60 * 1000;
const maximumAccuracyMeters = 250;
const maximumPastAgeMs = 10 * 60 * 1000;
const maximumFutureAgeMs = 2 * 60 * 1000;

export function normalizeGpsPayload(payload, receivedAt = new Date()) {
  const required = ['technicianId', 'jobId', 'latitude', 'longitude'];
  for (const key of required) {
    if (payload?.[key] === undefined || payload?.[key] === null) {
      throw new Error(`Missing ${key}`);
    }
  }
  const latitude = Number(payload.latitude);
  const longitude = Number(payload.longitude);
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
    throw new Error('Latitude is invalid');
  }
  if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    throw new Error('Longitude is invalid');
  }
  if (payload.isMocked === true) throw new Error('Mocked location is rejected');
  const accuracy = numberOrNull(payload.accuracy);
  if (accuracy !== null && (accuracy < 0 || accuracy > maximumAccuracyMeters)) {
    throw new Error('Location accuracy is insufficient');
  }
  const capturedAt = payload.timestamp == null
    ? receivedAt
    : new Date(payload.timestamp);
  if (Number.isNaN(capturedAt.getTime())) throw new Error('Timestamp is invalid');
  const ageMs = receivedAt.getTime() - capturedAt.getTime();
  if (ageMs > maximumPastAgeMs) throw new Error('Location update is stale');
  if (ageMs < -maximumFutureAgeMs) throw new Error('Location timestamp is in the future');
  return {
    technicianId: String(payload.technicianId),
    jobId: String(payload.jobId),
    customerId: payload.customerId ? String(payload.customerId) : null,
    adminBranchId: payload.adminBranchId ? String(payload.adminBranchId) : null,
    latitude,
    longitude,
    destinationLatitude: Number(payload.destinationLatitude),
    destinationLongitude: Number(payload.destinationLongitude),
    heading: numberOrNull(payload.heading),
    bearing: numberOrNull(payload.bearing ?? payload.heading),
    speed: numberOrNull(payload.speed),
    accuracy,
    isMocked: false,
    isOnline: true,
    capturedAt: capturedAt.toISOString(),
    updatedAt: receivedAt.toISOString(),
  };
}

export async function persistGpsUpdate(update, firestore) {
  const technicianRef = firestore.collection('technician_locations')
    .doc(update.technicianId);
  const receivedAt = new Date();
  const previousHistoryWriteAt = lastHistoryWriteAtByTechnician
    .get(update.technicianId);
  const recordHistory = previousHistoryWriteAt === undefined ||
    receivedAt.getTime() - previousHistoryWriteAt >= historyIntervalMs;
  const historyRef = recordHistory
    ? technicianRef.collection('history').doc()
    : null;
  const data = {
    technicianId: update.technicianId,
    latitude: update.latitude,
    longitude: update.longitude,
    updatedAt: FieldValue.serverTimestamp(),
    // Use server receipt time for a trustworthy, ordered replay timeline.
    capturedAt: receivedAt,
    activeBookingId: update.jobId,
    branchId: update.adminBranchId,
    heading: update.heading,
    bearing: update.bearing,
    speed: update.speed,
    accuracy: update.accuracy,
    isMocked: false,
    isOnline: true,
  };
  const batch = firestore.batch();
  batch.set(technicianRef, data, { merge: true });
  if (historyRef) batch.set(historyRef, data);
  await batch.commit();
  if (recordHistory) {
    lastHistoryWriteAtByTechnician.set(update.technicianId, receivedAt.getTime());
  }
}

function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}
