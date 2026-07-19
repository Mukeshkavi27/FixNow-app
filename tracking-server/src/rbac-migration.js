export function planUserRoleMigration(user, options = {}) {
  if (user.role !== 'admin') return null;
  const superAdminUids = options.superAdminUids ?? new Set();
  if (superAdminUids.has(user.uid)) {
    return { role: 'superAdmin', rbacVersion: 1 };
  }
  const branchId = user.branchId || options.defaultBranchId;
  const branchName = user.branchName || options.defaultBranchName;
  if (!branchId) {
    return { blocked: true, reason: 'Legacy Admin has no branch assignment' };
  }
  return {
    role: 'branchAdmin',
    branchId,
    ...(branchName ? { branchName } : {}),
    rbacVersion: 1,
  };
}
