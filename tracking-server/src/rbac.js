export const roles = Object.freeze({
  superAdmin: 'superAdmin',
  branchAdmin: 'branchAdmin',
  technician: 'technician',
  customer: 'customer',
});

export const permissions = Object.freeze({
  monitorAllTracking: 'monitorAllTracking',
  monitorBranchTracking: 'monitorBranchTracking',
  publishAssignedTracking: 'publishAssignedTracking',
  viewOwnBookingTracking: 'viewOwnBookingTracking',
  manageGlobalOperations: 'manageGlobalOperations',
});

const matrix = new Map([
  [roles.superAdmin, new Set([
    permissions.monitorAllTracking,
    permissions.monitorBranchTracking,
    permissions.manageGlobalOperations,
  ])],
  [roles.branchAdmin, new Set([permissions.monitorBranchTracking])],
  [roles.technician, new Set([permissions.publishAssignedTracking])],
  [roles.customer, new Set([permissions.viewOwnBookingTracking])],
]);

export function normalizeRole(value) {
  const normalized = String(value ?? '').replace(/[^a-z0-9]/gi, '').toLowerCase();
  if (normalized === 'superadmin') return roles.superAdmin;
  if (normalized === 'branchadmin' || normalized === 'admin') {
    return roles.branchAdmin;
  }
  if (normalized === 'technician' || normalized === 'tech') {
    return roles.technician;
  }
  return roles.customer;
}

export function buildPrincipal(uid, profile) {
  const role = normalizeRole(profile?.role);
  if (profile?.isActive !== true) throw new Error('Account is inactive');
  if ((profile?.accountStatus ?? 'approved') !== 'approved') {
    throw new Error('Account is not approved');
  }
  if (role === roles.branchAdmin && !profile?.branchId) {
    throw new Error('Branch Admin is not assigned to a branch');
  }
  return Object.freeze({
    uid,
    role,
    branchId: profile?.branchId ?? null,
    permissions: matrix.get(role) ?? new Set(),
  });
}

export function hasPermission(principal, permission) {
  return principal?.permissions?.has(permission) === true;
}

export function canViewBookingTracking(principal, booking) {
  if (!principal || !booking) return false;
  if (hasPermission(principal, permissions.monitorAllTracking)) return true;
  if (hasPermission(principal, permissions.monitorBranchTracking)) {
    return Boolean(principal.branchId) && booking.branchId === principal.branchId;
  }
  if (principal.role === roles.technician) {
    return booking.technicianId === principal.uid;
  }
  return principal.role === roles.customer && booking.customerId === principal.uid;
}

export function canPublishTracking(principal, booking, technicianId) {
  return principal?.role === roles.technician
    && principal.uid === String(technicianId)
    && booking?.technicianId === principal.uid
    && booking?.branchId === principal.branchId;
}
