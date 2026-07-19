import test from 'node:test';
import assert from 'node:assert/strict';

import { planBookingBranchMigration } from '../src/booking-branch-migration.js';

const branches = [
  { id: 'chennai', name: 'FixNow Chennai', city: 'Chennai' },
  { id: 'bengaluru', name: 'FixNow Bengaluru', city: 'Bengaluru' },
];

test('keeps bookings that already have a branch unchanged', () => {
  assert.equal(
    planBookingBranchMigration({ branchId: 'chennai' }, { branches }),
    null,
  );
});

test('uses a unique explicit legacy branch name before customer metadata', () => {
  assert.deepEqual(
    planBookingBranchMigration(
      { branchName: 'FixNow Bengaluru' },
      { branches, customer: { branchId: 'chennai' } },
    ),
    {
      branchId: 'bengaluru',
      branchName: 'FixNow Bengaluru',
      source: 'unique legacy branch name',
    },
  );
});

test('preserves the customer branch relationship when no name is available', () => {
  assert.deepEqual(
    planBookingBranchMigration({}, {
      branches,
      customer: { branchId: 'chennai' },
    }),
    {
      branchId: 'chennai',
      branchName: 'FixNow Chennai',
      source: 'customer relationship',
    },
  );
});

test('blocks unresolved and ambiguous bookings instead of guessing', () => {
  assert.equal(
    planBookingBranchMigration({}, { branches }).blocked,
    true,
  );
  assert.equal(
    planBookingBranchMigration(
      { branchName: 'Chennai' },
      {
        branches: [
          ...branches,
          { id: 'chennai-2', name: 'Chennai', city: 'Chennai' },
        ],
      },
    ).blocked,
    true,
  );
});
