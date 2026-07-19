export function planBookingBranchMigration(
  booking,
  {
    branches = [],
    customer,
    defaultBranchId,
  } = {},
) {
  if (booking.branchId) return null;
  const byId = new Map(branches.map((branch) => [branch.id, branch]));
  const bookingBranchName = normalize(booking.branchName);
  if (bookingBranchName) {
    const matches = branches.filter((branch) => [
      branch.id,
      branch.name,
      branch.city,
      ...(branch.aliases ?? []),
    ].some((value) => normalize(value) === bookingBranchName));
    if (matches.length === 1) {
      return branchPlan(matches[0], 'unique legacy branch name');
    }
    if (matches.length > 1) {
      return blocked('Legacy branch name matches multiple branches');
    }
  }

  const customerBranch = customer?.branchId
    ? byId.get(customer.branchId)
    : null;
  if (customerBranch) return branchPlan(customerBranch, 'customer relationship');

  const fallback = defaultBranchId ? byId.get(defaultBranchId) : null;
  if (fallback) return branchPlan(fallback, 'explicit default branch');
  return blocked('Cannot derive branch without changing booking relationships');
}

function branchPlan(branch, source) {
  return {
    branchId: branch.id,
    branchName: branch.name,
    source,
  };
}

function blocked(reason) {
  return { blocked: true, reason };
}

function normalize(value) {
  return String(value ?? '').trim().toLowerCase().replace(/[^a-z0-9]/g, '');
}
