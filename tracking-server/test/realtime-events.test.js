import test from 'node:test';
import assert from 'node:assert/strict';
import { bookingRealtimeEvent, technicianLiveStatus } from '../src/realtime-events.js';

test('maps booking workflow changes to public socket events', () => {
  assert.equal(bookingRealtimeEvent({ status: 'booked' }, { status: 'technicianAssigned' }).name, 'bookingAssigned');
  assert.equal(bookingRealtimeEvent({ status: 'technicianAssigned' }, { status: 'accepted' }).name, 'bookingAccepted');
  assert.equal(bookingRealtimeEvent({ status: 'accepted' }, { status: 'onTheWay' }).name, 'bookingStarted');
  assert.equal(bookingRealtimeEvent({ status: 'serviceStarted' }, { status: 'serviceCompleted' }).name, 'bookingCompleted');
  assert.equal(bookingRealtimeEvent({ status: 'accepted' }, { status: 'accepted' }), null);
});

test('derives monitoring status from online state and booking workflow', () => {
  assert.equal(technicianLiveStatus({ isOnline: false }, null), 'Offline');
  assert.equal(technicianLiveStatus({ isOnline: true }, { status: 'onTheWay' }), 'Driving');
  assert.equal(technicianLiveStatus({ isOnline: true }, { status: 'arrived' }), 'Reached Customer');
  assert.equal(technicianLiveStatus({ isOnline: true }, { status: 'serviceStarted' }), 'Repairing');
  assert.equal(technicianLiveStatus({ isOnline: true }, null), 'Idle');
});
