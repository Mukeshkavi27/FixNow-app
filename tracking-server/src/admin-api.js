import { FieldValue } from 'firebase-admin/firestore';
import { hasPermission, permissions, roles } from './rbac.js';

export function validateBranchAdminInput(body) {
  const input = {
    name: String(body?.name ?? '').trim(),
    email: String(body?.email ?? '').trim().toLowerCase(),
    phone: String(body?.phone ?? '').trim(),
    password: String(body?.password ?? ''),
    branchId: String(body?.branchId ?? '').trim(),
  };
  if (input.name.length < 2) throw new Error('Name is required');
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.email)) {
    throw new Error('A valid email is required');
  }
  if (input.phone.length < 7) throw new Error('A valid phone is required');
  if (input.password.length < 6) {
    throw new Error('Temporary password must contain at least 6 characters');
  }
  if (!input.branchId) throw new Error('Branch assignment is required');
  return input;
}

export function validateBranchTransferInput(body) {
  const branchId = String(body?.branchId ?? '').trim();
  if (!branchId) throw new Error('Target branch is required');
  return { branchId };
}

export function validateTechnicianTransferInput(body) {
  const { branchId } = validateBranchTransferInput(body);
  return {
    branchId,
    futureRevenueStaysWithPreviousBranch:
      body?.futureRevenueStaysWithPreviousBranch === true,
  };
}

export function requireSuperAdmin(req, res, next) {
  if (!hasPermission(req.principal, permissions.manageGlobalOperations)) {
    res.status(403).json({ ok: false, error: 'Super Admin permission is required' });
    return;
  }
  next();
}

export function registerSuperAdminRoutes(app, { auth, firestore }) {
  app.use('/api/admin', requireSuperAdmin);

  app.post('/api/admin/branch-admins', async (req, res) => {
    let createdUser;
    try {
      const input = validateBranchAdminInput(req.body);
      const branchRef = firestore.collection('branches').doc(input.branchId);
      const branch = await branchRef.get();
      if (!branch.exists) throw new Error('Assigned branch was not found');
      if (branch.data()?.isActive === false) {
        throw new Error('Branch Admin cannot be assigned to an inactive branch');
      }

      createdUser = await auth.createUser({
        email: input.email,
        password: input.password,
        displayName: input.name,
        disabled: false,
      });
      const userRef = firestore.collection('users').doc(createdUser.uid);
      const auditRef = firestore.collection('audit_logs').doc();
      const batch = firestore.batch();
      batch.set(userRef, {
        uid: createdUser.uid,
        name: input.name,
        email: input.email,
        phone: input.phone,
        phoneNormalized: normalizeIndianMobile(input.phone),
        role: roles.branchAdmin,
        accountStatus: 'approved',
        isActive: true,
        branchId: branch.id,
        branchName: branch.data()?.name ?? '',
        createdAt: FieldValue.serverTimestamp(),
        createdBy: req.principal.uid,
      });
      batch.update(branchRef, {
        branchAdminIds: FieldValue.arrayUnion(createdUser.uid),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(auditRef, auditData(req.principal, {
        action: 'branchAdmin.created',
        targetId: createdUser.uid,
        branchId: branch.id,
        summary: `Created Branch Admin ${input.email}`,
      }));
      await batch.commit();
      res.status(201).json({ ok: true, uid: createdUser.uid });
    } catch (error) {
      if (createdUser) await auth.deleteUser(createdUser.uid).catch(() => {});
      const conflict = error?.code === 'auth/email-already-exists';
      res.status(conflict ? 409 : 400).json({ ok: false, error: error.message });
    }
  });

  app.post('/api/admin/branch-admins/:uid/password-reset', async (req, res) => {
    try {
      const { profile, authUser } = await branchAdminByUid(
        req.params.uid,
        { auth, firestore },
      );
      const resetLink = await auth.generatePasswordResetLink(authUser.email);
      await firestore.collection('audit_logs').add(auditData(req.principal, {
        action: 'branchAdmin.passwordResetRequested',
        targetId: authUser.uid,
        branchId: profile.branchId,
        summary: `Generated password reset for ${authUser.email}`,
      }));
      res.json({ ok: true, resetLink });
    } catch (error) {
      res.status(400).json({ ok: false, error: error.message });
    }
  });

  app.patch('/api/admin/branch-admins/:uid/status', async (req, res) => {
    try {
      if (typeof req.body?.isActive !== 'boolean') {
        throw new Error('isActive must be a boolean');
      }
      const { profile, authUser, ref } = await branchAdminByUid(
        req.params.uid,
        { auth, firestore },
      );
      await auth.updateUser(authUser.uid, { disabled: !req.body.isActive });
      const auditRef = firestore.collection('audit_logs').doc();
      const batch = firestore.batch();
      batch.update(ref, {
        isActive: req.body.isActive,
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(auditRef, auditData(req.principal, {
        action: req.body.isActive
          ? 'branchAdmin.activated'
          : 'branchAdmin.deactivated',
        targetId: authUser.uid,
        branchId: profile.branchId,
        summary: `${req.body.isActive ? 'Activated' : 'Deactivated'} ${authUser.email}`,
      }));
      await batch.commit();
      res.json({ ok: true });
    } catch (error) {
      res.status(400).json({ ok: false, error: error.message });
    }
  });

  app.patch('/api/admin/branch-admins/:uid/branch', async (req, res) => {
    try {
      const { branchId } = validateBranchTransferInput(req.body);
      const { profile, authUser, ref } = await branchAdminByUid(
        req.params.uid,
        { auth, firestore },
      );
      if (profile.branchId === branchId) {
        throw new Error('Branch Admin is already assigned to this branch');
      }

      const targetBranchRef = firestore.collection('branches').doc(branchId);
      const targetBranch = await targetBranchRef.get();
      if (!targetBranch.exists) throw new Error('Target branch was not found');
      if (targetBranch.data()?.isActive === false) {
        throw new Error('Branch Admin cannot be transferred to an inactive branch');
      }

      const auditRef = firestore.collection('audit_logs').doc();
      const batch = firestore.batch();
      if (profile.branchId) {
        batch.update(firestore.collection('branches').doc(profile.branchId), {
          branchAdminIds: FieldValue.arrayRemove(authUser.uid),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      batch.update(targetBranchRef, {
        branchAdminIds: FieldValue.arrayUnion(authUser.uid),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.update(ref, {
        branchId,
        branchName: targetBranch.data()?.name ?? '',
        transferredAt: FieldValue.serverTimestamp(),
        transferredBy: req.principal.uid,
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(auditRef, auditData(req.principal, {
        action: 'branchAdmin.transferred',
        targetId: authUser.uid,
        branchId,
        summary: `Transferred ${authUser.email} from ${profile.branchName ?? profile.branchId ?? 'unassigned'} to ${targetBranch.data()?.name ?? branchId}`,
      }));
      await batch.commit();
      res.json({
        ok: true,
        uid: authUser.uid,
        branchId,
        branchName: targetBranch.data()?.name ?? '',
      });
    } catch (error) {
      res.status(400).json({ ok: false, error: error.message });
    }
  });

  app.patch('/api/admin/technicians/:uid/branch', async (req, res) => {
    try {
      const { branchId, futureRevenueStaysWithPreviousBranch } =
        validateTechnicianTransferInput(req.body);
      const technicianRef = firestore.collection('users').doc(String(req.params.uid));
      const targetBranchRef = firestore.collection('branches').doc(branchId);
      const activeJobRef = firestore.collection('technician_active_jobs').doc(String(req.params.uid));
      const [technician, targetBranch, activeJob, historicBills] = await Promise.all([
        technicianRef.get(),
        targetBranchRef.get(),
        activeJobRef.get(),
        firestore.collection('bills').where('technicianId', '==', String(req.params.uid)).get(),
      ]);
      const technicianData = technician.data();
      if (!technician.exists || technicianData?.role !== roles.technician) {
        throw new Error('Technician account was not found');
      }
      if (!targetBranch.exists || targetBranch.data()?.isActive === false) {
        throw new Error('Destination branch is unavailable');
      }
      if (activeJob.exists) {
        throw new Error('Complete the technician active job before changing branches');
      }
      const previousBranchId = technicianData.branchId;
      const previousRevenueBranchId = technicianData.nativeBranchId || previousBranchId;
      const previousRevenueBranchName = technicianData.nativeBranchName || technicianData.branchName || previousRevenueBranchId;
      if (!previousRevenueBranchId) {
        throw new Error('Technician revenue branch could not be determined');
      }
      const futureRevenueBranchId = futureRevenueStaysWithPreviousBranch
        ? previousRevenueBranchId
        : branchId;
      const futureRevenueBranchName = futureRevenueStaysWithPreviousBranch
        ? previousRevenueBranchName
        : (targetBranch.data()?.name || branchId);
      const legacyBills = historicBills.docs.filter((bill) => !bill.data().revenueBranchId);
      // Lock old bill ownership in chunks before changing the technician's
      // future reporting branch. This supports long-lived technicians too.
      for (let start = 0; start < legacyBills.length; start += 450) {
        const ownershipBatch = firestore.batch();
        legacyBills.slice(start, start + 450).forEach((bill) => {
          ownershipBatch.update(bill.ref, {
            revenueBranchId: previousRevenueBranchId,
            revenueBranchLockedAt: FieldValue.serverTimestamp(),
          });
        });
        await ownershipBatch.commit();
      }
      const auditRef = firestore.collection('audit_logs').doc();
      const batch = firestore.batch();
      batch.update(technicianRef, {
        branchId,
        branchName: targetBranch.data()?.name || '',
        nativeBranchId: futureRevenueBranchId,
        nativeBranchName: futureRevenueBranchName,
        transferredAt: FieldValue.serverTimestamp(),
        transferredBy: req.principal.uid,
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(auditRef, auditData(req.principal, {
        action: 'technician.transferred',
        targetType: 'technician',
        targetId: technicianRef.id,
        branchId,
        summary: `Transferred ${technicianData.email || technicianRef.id} to ${targetBranch.data()?.name || branchId}; future revenue belongs to ${futureRevenueBranchName}. Existing bills remain with ${previousRevenueBranchName}.`,
      }));
      await batch.commit();
      res.json({ ok: true, branchId, futureRevenueBranchId });
    } catch (error) {
      res.status(400).json({ ok: false, error: error.message });
    }
  });
}

function normalizeIndianMobile(value) {
  const digits = String(value ?? '').replace(/\D/g, '');
  if (/^[6-9]\d{9}$/.test(digits)) return `+91${digits}`;
  if (/^91[6-9]\d{9}$/.test(digits)) return `+${digits}`;
  throw new Error('Enter a valid Indian mobile number');
}

async function branchAdminByUid(uid, { auth, firestore }) {
  const ref = firestore.collection('users').doc(String(uid));
  const snapshot = await ref.get();
  if (!snapshot.exists || snapshot.data()?.role !== roles.branchAdmin) {
    throw new Error('Branch Admin was not found');
  }
  const authUser = await auth.getUser(snapshot.id);
  return { profile: snapshot.data(), authUser, ref };
}

function auditData(principal, details) {
  return {
    actorId: principal.uid,
    actorRole: principal.role,
    action: details.action,
    targetType: details.targetType || 'branchAdmin',
    targetId: details.targetId,
    branchId: details.branchId,
    summary: details.summary,
    createdAt: FieldValue.serverTimestamp(),
  };
}
