import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildPrincipal,
  canPublishTracking,
  canViewBookingTracking,
  normalizeRole,
  roles,
} from '../src/rbac.js';

const booking = {
  customerId: 'customer-1',
  technicianId: 'tech-1',
  branchId: 'branch-a',
};

test('legacy admin is migrated in memory to least-privileged Branch Admin', () => {
  assert.equal(normalizeRole('admin'), roles.branchAdmin);
});

test('Branch Admin can only monitor their assigned branch', () => {
  const branchAdmin = buildPrincipal('admin-a', {
    role: 'branchAdmin', isActive: true, accountStatus: 'approved', branchId: 'branch-a',
  });
  assert.equal(canViewBookingTracking(branchAdmin, booking), true);
  assert.equal(canViewBookingTracking(branchAdmin, { ...booking, branchId: 'branch-b' }), false);
});

test('technician cannot impersonate another technician or publish another job', () => {
  const technician = buildPrincipal('tech-1', {
    role: 'technician', isActive: true, accountStatus: 'approved', branchId: 'branch-a',
  });
  assert.equal(canPublishTracking(technician, booking, 'tech-1'), true);
  assert.equal(canPublishTracking(technician, booking, 'tech-2'), false);
  assert.equal(canPublishTracking(technician, { ...booking, technicianId: 'tech-2' }, 'tech-1'), false);
});

test('inactive and unassigned administrative accounts are rejected', () => {
  assert.throws(() => buildPrincipal('inactive', {
    role: 'customer', isActive: false, accountStatus: 'approved',
  }), /inactive/);
  assert.throws(() => buildPrincipal('unassigned', {
    role: 'branchAdmin', isActive: true, accountStatus: 'approved',
  }), /assigned to a branch/);
});
