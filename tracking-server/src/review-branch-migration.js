export function planReviewBranchMigration(review, { booking } = {}) {
  if (review.branchId) return null;
  const branchId = String(booking?.branchId ?? '').trim();
  if (!branchId) {
    return {
      blocked: true,
      reason: 'Linked booking has no branch assignment',
    };
  }
  if (booking.technicianId !== review.technicianId ||
      booking.customerId !== review.customerId) {
    return {
      blocked: true,
      reason: 'Review relationships do not match the linked booking',
    };
  }
  return { branchId, source: 'linked booking relationship' };
}
