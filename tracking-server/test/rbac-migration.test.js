import test from 'node:test';
import assert from 'node:assert/strict';
import { planUserRoleMigration } from '../src/rbac-migration.js';

test('legacy Admin becomes Branch Admin without deleting profile data', () => {
  const change = planUserRoleMigration({
    uid: 'admin-1', role: 'admin', branchId: 'branch-a', name: 'Existing Admin',
  });
  assert.deepEqual(change, {
    role: 'branchAdmin', branchId: 'branch-a', rbacVersion: 1,
  });
});

test('explicitly selected legacy Admin becomes Super Admin', () => {
  const change = planUserRoleMigration(
    { uid: 'owner-1', role: 'admin', branchId: 'branch-a' },
    { superAdminUids: new Set(['owner-1']) },
  );
  assert.deepEqual(change, { role: 'superAdmin', rbacVersion: 1 });
});

test('migration blocks rather than guessing a missing branch', () => {
  const change = planUserRoleMigration({ uid: 'admin-1', role: 'admin' });
  assert.equal(change.blocked, true);
});
