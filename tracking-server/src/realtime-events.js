const bookingEventByStatus = Object.freeze({
  technicianAssigned: 'bookingAssigned',
  accepted: 'bookingAccepted',
  onTheWay: 'bookingStarted',
  arrived: 'statusChanged',
  customerConfirmedArrival: 'statusChanged',
  estimateSent: 'statusChanged',
  estimateApproved: 'statusChanged',
  serviceStarted: 'statusChanged',
  serviceCompleted: 'bookingCompleted',
  billGenerated: 'statusChanged',
  closed: 'bookingCompleted',
  onHold: 'statusChanged',
});

export function bookingRealtimeEvent(before, after) {
  if (!after || before?.status === after.status) return null;
  const name = bookingEventByStatus[after.status] ?? 'statusChanged';
  return { name, payload: { ...after, event: name } };
}

export function technicianLiveStatus(location, booking) {
  if (!location?.isOnline) return 'Offline';
  if (booking?.status === 'onTheWay') return 'Driving';
  if (booking?.status === 'arrived' ||
      booking?.status === 'customerConfirmedArrival' ||
      booking?.status === 'estimateSent' ||
      booking?.status === 'estimateApproved') return 'Reached Customer';
  if (booking?.status === 'serviceStarted') return 'Repairing';
  return 'Idle';
}

function adminRooms(io, branchId) {
  const rooms = [io.to('admin:global')];
  if (branchId) rooms.push(io.to(`admin:branch:${branchId}`));
  return rooms;
}

function emitToAdmins(io, branchId, event, payload) {
  for (const room of adminRooms(io, branchId)) room.emit(event, payload);
}

export function startRealtimeEventBridge({ firestore, io, logger = console }) {
  const stops = [];
  const previousBookings = new Map();
  stops.push(firestore.collection('bookings').onSnapshot((snapshot) => {
    for (const change of snapshot.docChanges()) {
      const before = previousBookings.get(change.doc.id) ?? null;
      const after = change.type === 'removed' ? null : { id: change.doc.id, ...change.doc.data() };
      if (after) previousBookings.set(change.doc.id, after);
      else previousBookings.delete(change.doc.id);
      const event = bookingRealtimeEvent(before, after);
      if (!event) continue;
      const payload = event.payload;
      if (payload.technicianId) io.to(`user:${payload.technicianId}`).emit(event.name, payload);
      if (payload.customerId) io.to(`user:${payload.customerId}`).emit(event.name, payload);
      emitToAdmins(io, payload.branchId, event.name, payload);
      if (event.name !== 'statusChanged') {
        emitToAdmins(io, payload.branchId, 'statusChanged', payload);
      }
    }
  }, (error) => logger.error('Booking realtime bridge failed:', error)));

  stops.push(firestore.collection('technician_locations').onSnapshot((snapshot) => {
    for (const change of snapshot.docChanges()) {
      if (change.type === 'removed') continue;
      const location = { technicianId: change.doc.id, ...change.doc.data() };
      const payload = { ...location, event: 'locationUpdated' };
      io.to(`user:${location.technicianId}`).emit('locationUpdated', payload);
      emitToAdmins(io, location.branchId, 'locationUpdated', payload);
    }
  }, (error) => logger.error('Location realtime bridge failed:', error)));

  stops.push(firestore.collection('attendance').onSnapshot((snapshot) => {
    for (const change of snapshot.docChanges()) {
      if (change.type === 'removed') continue;
      const attendance = { id: change.doc.id, ...change.doc.data(), event: 'attendanceUpdated' };
      io.to(`user:${attendance.technicianId}`).emit('attendanceUpdated', attendance);
      emitToAdmins(io, attendance.branchId, 'attendanceUpdated', attendance);
    }
  }, (error) => logger.error('Attendance realtime bridge failed:', error)));
  return () => stops.forEach((stop) => stop());
}

export async function socketSyncFor(principal, firestore) {
  if (principal.role === 'technician') {
    const [bookings, location, attendance] = await Promise.all([
      firestore.collection('bookings').where('technicianId', '==', principal.uid).get(),
      firestore.collection('technician_locations').doc(principal.uid).get(),
      firestore.collection('attendance').where('technicianId', '==', principal.uid).get(),
    ]);
    return {
      bookings: bookings.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
      location: location.exists ? { technicianId: location.id, ...location.data() } : null,
      attendance: attendance.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
    };
  }
  const bookingQuery = principal.role === 'superAdmin'
    ? firestore.collection('bookings')
    : firestore.collection('bookings').where('branchId', '==', principal.branchId);
  const locationQuery = principal.role === 'superAdmin'
    ? firestore.collection('technician_locations')
    : firestore.collection('technician_locations').where('branchId', '==', principal.branchId);
  const [bookings, locations] = await Promise.all([bookingQuery.get(), locationQuery.get()]);
  return {
    bookings: bookings.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
    locations: locations.docs.map((doc) => ({ technicianId: doc.id, ...doc.data() })),
  };
}
