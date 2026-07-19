import { FieldValue } from 'firebase-admin/firestore';

export function normalizeGpsPayload(payload) {
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
    accuracy: numberOrNull(payload.accuracy),
    isOnline: true,
    updatedAt: payload.timestamp ?? new Date().toISOString(),
  };
}

export async function persistGpsUpdate(update, firestore) {
  const technicianRef = firestore.collection('technician_locations')
    .doc(update.technicianId);
  const historyRef = technicianRef.collection('history').doc();
  const data = {
    technicianId: update.technicianId,
    latitude: update.latitude,
    longitude: update.longitude,
    updatedAt: FieldValue.serverTimestamp(),
    capturedAt: new Date(update.updatedAt),
    activeBookingId: update.jobId,
    branchId: update.adminBranchId,
    heading: update.heading,
    bearing: update.bearing,
    speed: update.speed,
    accuracy: update.accuracy,
    isOnline: true,
  };
  const batch = firestore.batch();
  batch.set(technicianRef, data, { merge: true });
  batch.set(historyRef, data);
  await batch.commit();
}

function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}
