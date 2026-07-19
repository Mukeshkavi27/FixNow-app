import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branches/branch_info.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/domain/app_user.dart';
import '../domain/audit_log_entry.dart';

final superAdminRepositoryProvider = Provider<SuperAdminRepository>((ref) {
  return SuperAdminRepository(ref.watch(firebaseRefsProvider).firestore);
});

class SuperAdminRepository {
  SuperAdminRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<AppUser>> watchBranchAdmins() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.branchAdmin.name)
        .snapshots()
        .map((snapshot) {
      final users = snapshot.docs.map(AppUser.fromFirestore).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return users;
    });
  }

  Stream<List<AuditLogEntry>> watchAuditLogs({int limit = 100}) {
    return _firestore
        .collection('audit_logs')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(AuditLogEntry.fromFirestore).toList(),
        );
  }

  Future<String> createBranch({
    required BranchInfo branch,
    required String actorId,
  }) async {
    final branchRef = _firestore.collection('branches').doc();
    final auditRef = _firestore.collection('audit_logs').doc();
    final saved = BranchInfo(
      id: branchRef.id,
      name: branch.name.trim(),
      city: branch.city.trim(),
      latitude: branch.latitude,
      longitude: branch.longitude,
      aliases: branch.aliases,
      radiusMeters: branch.radiusMeters,
      isActive: true,
    );
    final batch = _firestore.batch();
    batch.set(branchRef, {
      ...saved.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      auditRef,
      _auditData(
        actorId: actorId,
        action: 'branch.created',
        targetType: 'branch',
        targetId: branchRef.id,
        branchId: branchRef.id,
        summary: 'Created ${saved.name}',
      ),
    );
    await batch.commit();
    return branchRef.id;
  }

  Future<void> updateBranch({
    required BranchInfo branch,
    required String actorId,
  }) async {
    final branchRef = _firestore.collection('branches').doc(branch.id);
    final auditRef = _firestore.collection('audit_logs').doc();
    final batch = _firestore.batch();
    batch.update(branchRef, {
      ...branch.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      auditRef,
      _auditData(
        actorId: actorId,
        action: 'branch.updated',
        targetType: 'branch',
        targetId: branch.id,
        branchId: branch.id,
        summary: 'Updated ${branch.name}',
      ),
    );
    await batch.commit();
  }

  Future<void> setBranchActive({
    required BranchInfo branch,
    required bool isActive,
    required String actorId,
  }) async {
    final branchRef = _firestore.collection('branches').doc(branch.id);
    final auditRef = _firestore.collection('audit_logs').doc();
    final batch = _firestore.batch();
    batch.update(branchRef, {
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      auditRef,
      _auditData(
        actorId: actorId,
        action: isActive ? 'branch.activated' : 'branch.deactivated',
        targetType: 'branch',
        targetId: branch.id,
        branchId: branch.id,
        summary: '${isActive ? 'Activated' : 'Deactivated'} ${branch.name}',
      ),
    );
    await batch.commit();
  }

  Map<String, dynamic> _auditData({
    required String actorId,
    required String action,
    required String targetType,
    required String targetId,
    required String summary,
    String? branchId,
  }) {
    return {
      'actorId': actorId,
      'actorRole': UserRole.superAdmin.name,
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'summary': summary,
      if (branchId != null) 'branchId': branchId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
