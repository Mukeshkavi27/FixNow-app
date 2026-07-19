import test from 'node:test';
import assert from 'node:assert/strict';

import { planReviewBranchMigration } from '../src/review-branch-migration.js';

test('review migration preserves the linked booking relationship', () => {
  assert.deepEqual(
    planReviewBranchMigration(
      { technicianId: 'tech-1', customerId: 'customer-1' },
      {
        booking: {
          branchId: 'branch-a',
          technicianId: 'tech-1',
          customerId: 'customer-1',
        },
      },
    ),
    { branchId: 'branch-a', source: 'linked booking relationship' },
  );
});

test('review migration blocks missing or mismatched relationships', () => {
  assert.equal(
    planReviewBranchMigration(
      { technicianId: 'tech-1', customerId: 'customer-1' },
      { booking: null },
    ).blocked,
    true,
  );
  assert.equal(
    planReviewBranchMigration(
      { technicianId: 'tech-1', customerId: 'customer-1' },
      {
        booking: {
          branchId: 'branch-a',
          technicianId: 'tech-2',
          customerId: 'customer-1',
        },
      },
    ).blocked,
    true,
  );
});
