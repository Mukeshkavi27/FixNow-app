import test from 'node:test';
import assert from 'node:assert/strict';
import {
  requireSuperAdmin,
  registerSuperAdminRoutes,
  validateBranchAdminInput,
  validateBranchTransferInput,
} from '../src/admin-api.js';
import { buildPrincipal } from '../src/rbac.js';

test('Branch Admin payload is normalized and requires a branch', () => {
  const input = validateBranchAdminInput({
    name: ' Branch Admin ',
    email: 'ADMIN@EXAMPLE.COM ',
    phone: '9999999999',
    password: 'Temporary#123',
    branchId: 'branch-a',
  });
  assert.equal(input.name, 'Branch Admin');
  assert.equal(input.email, 'admin@example.com');
  assert.equal(input.branchId, 'branch-a');
});

test('Branch Admin creation rejects weak passwords and missing branches', () => {
  assert.throws(() => validateBranchAdminInput({
    name: 'Admin', email: 'admin@example.com', phone: '9999999999',
    password: 'short', branchId: 'branch-a',
  }), /6 characters/);
  assert.throws(() => validateBranchAdminInput({
    name: 'Admin', email: 'admin@example.com', phone: '9999999999',
    password: 'Temporary#123', branchId: '',
  }), /Branch assignment/);
});

test('Branch Admin transfer requires and normalizes a target branch', () => {
  assert.deepEqual(
    validateBranchTransferInput({ branchId: ' branch-b ' }),
    { branchId: 'branch-b' },
  );
  assert.throws(
    () => validateBranchTransferInput({ branchId: '  ' }),
    /Target branch is required/,
  );
});

test('management middleware rejects Branch Admin and permits Super Admin', () => {
  const branchAdmin = buildPrincipal('branch-admin', {
    role: 'branchAdmin', isActive: true, accountStatus: 'approved', branchId: 'a',
  });
  let statusCode;
  let responseBody;
  let nextCalled = false;
  requireSuperAdmin(
    { principal: branchAdmin },
    {
      status(code) { statusCode = code; return this; },
      json(body) { responseBody = body; },
    },
    () => { nextCalled = true; },
  );
  assert.equal(statusCode, 403);
  assert.equal(responseBody.ok, false);
  assert.equal(nextCalled, false);

  const superAdmin = buildPrincipal('super-admin', {
    role: 'superAdmin', isActive: true, accountStatus: 'approved',
  });
  requireSuperAdmin(
    { principal: superAdmin },
    { status() { throw new Error('should not reject'); } },
    () => { nextCalled = true; },
  );
  assert.equal(nextCalled, true);
});

test('Branch Admin transfer moves branch membership and profile atomically', async () => {
  const routes = new Map();
  const app = {
    use() {},
    post(path, handler) { routes.set(`POST ${path}`, handler); },
    patch(path, handler) { routes.set(`PATCH ${path}`, handler); },
  };
  const updates = [];
  const sets = [];
  const snapshots = new Map([
    ['users/admin-1', {
      exists: true,
      id: 'admin-1',
      data: () => ({
        role: 'branchAdmin',
        branchId: 'branch-a',
        branchName: 'FixNow Chennai',
      }),
    }],
    ['branches/branch-b', {
      exists: true,
      id: 'branch-b',
      data: () => ({ name: 'FixNow Bengaluru', isActive: true }),
    }],
  ]);
  const firestore = {
    collection(name) {
      return {
        doc(id = 'audit-1') {
          const path = `${name}/${id}`;
          return {
            id,
            path,
            async get() {
              return snapshots.get(path) ?? { exists: false, id, data: () => null };
            },
          };
        },
      };
    },
    batch() {
      return {
        update(ref, data) { updates.push([ref.path, data]); },
        set(ref, data) { sets.push([ref.path, data]); },
        async commit() {},
      };
    },
  };
  const auth = {
    async getUser(uid) {
      return { uid, email: 'manager@fixnow.test' };
    },
  };
  registerSuperAdminRoutes(app, { auth, firestore });
  const handler = routes.get('PATCH /api/admin/branch-admins/:uid/branch');
  let response;
  let statusCode = 200;
  await handler(
    {
      params: { uid: 'admin-1' },
      body: { branchId: 'branch-b' },
      principal: { uid: 'super-1', role: 'superAdmin' },
    },
    {
      status(code) { statusCode = code; return this; },
      json(body) { response = body; },
    },
  );

  assert.equal(statusCode, 200);
  assert.equal(response.ok, true);
  assert.equal(response.branchId, 'branch-b');
  const profileUpdate = updates.find(([path]) => path === 'users/admin-1');
  assert.equal(profileUpdate[1].branchId, 'branch-b');
  assert.equal(profileUpdate[1].branchName, 'FixNow Bengaluru');
  assert.equal(updates.some(([path]) => path === 'branches/branch-a'), true);
  assert.equal(updates.some(([path]) => path === 'branches/branch-b'), true);
  assert.equal(sets.some(([path]) => path === 'audit_logs/audit-1'), true);
});
