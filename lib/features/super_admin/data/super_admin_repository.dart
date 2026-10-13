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

  Future<FinancialBranchBackfillResult> backfillFinancialBranches({
    required String actorId,
  }) async {
    final results = await Future.wait([
      _firestore.collection('users').get(),
      _firestore.collection('bookings').get(),
      _firestore.collection('bills').get(),
      _firestore.collection('technician_incentives').get(),
    ]);
    final users = results[0];
    final bookings = results[1];
    final bills = results[2];
    final incentives = results[3];
    final technicianBranches = <String, String>{};
    final bookingBranches = <String, String>{};
    var techniciansUpdated = 0;
    var billsUpdated = 0;
    var incentivesUpdated = 0;
    var batch = _firestore.batch();
    var writes = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (writes == 0 || (!force && writes < 450)) return;
      await batch.commit();
      batch = _firestore.batch();
      writes = 0;
    }

    for (final user in users.docs) {
      final data = user.data();
      if (data['role'] != UserRole.technician.name) continue;
      final currentBranchId = data['branchId'] as String?;
      final nativeBranchId = data['nativeBranchId'] as String?;
      final revenueBranchId = (nativeBranchId?.trim().isNotEmpty ?? false)
          ? nativeBranchId!
          : currentBranchId;
      if (revenueBranchId == null || revenueBranchId.isEmpty) continue;
      technicianBranches[user.id] = revenueBranchId;
      if (nativeBranchId == null || nativeBranchId.isEmpty) {
        batch.update(user.reference, {
          'nativeBranchId': revenueBranchId,
          'nativeBranchName': data['branchName'] as String? ?? '',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        writes++;
        techniciansUpdated++;
        await commitIfNeeded();
      }
    }
    for (final booking in bookings.docs) {
      final branchId = booking.data()['branchId'] as String?;
      if (branchId != null && branchId.isNotEmpty) {
        bookingBranches[booking.id] = branchId;
      }
    }
    for (final bill in bills.docs) {
      final data = bill.data();
      final existingBranchId = data['branchId'] as String?;
      final serviceBranchId = (existingBranchId?.trim().isNotEmpty ?? false)
          ? existingBranchId
          : bookingBranches[data['bookingId'] as String?];
      final existingRevenueBranchId = data['revenueBranchId'] as String?;
      final revenueBranchId =
          (existingRevenueBranchId?.trim().isNotEmpty ?? false)
              ? existingRevenueBranchId
              : technicianBranches[data['technicianId'] as String?] ??
                  serviceBranchId;
      final updates = <String, Object?>{};
      if ((existingBranchId == null || existingBranchId.isEmpty) &&
          serviceBranchId != null) {
        updates['branchId'] = serviceBranchId;
      }
      if ((existingRevenueBranchId == null ||
              existingRevenueBranchId.isEmpty) &&
          revenueBranchId != null) {
        updates['revenueBranchId'] = revenueBranchId;
      }
      if (updates.isEmpty) continue;
      batch.update(bill.reference, updates);
      writes++;
      billsUpdated++;
      await commitIfNeeded();
    }
    for (final incentive in incentives.docs) {
      final data = incentive.data();
      final existingRevenueBranchId = data['revenueBranchId'] as String?;
      if (existingRevenueBranchId != null &&
          existingRevenueBranchId.isNotEmpty) {
        continue;
      }
      final revenueBranchId =
          technicianBranches[data['technicianId'] as String?] ??
              data['branchId'] as String?;
      if (revenueBranchId == null || revenueBranchId.isEmpty) continue;
      batch.update(incentive.reference, {
        'revenueBranchId': revenueBranchId,
      });
      writes++;
      incentivesUpdated++;
      await commitIfNeeded();
    }
    final auditRef = _firestore.collection('audit_logs').doc();
    batch.set(
      auditRef,
      _auditData(
        actorId: actorId,
        action: 'finance.branchOwnershipBackfilled',
        targetType: 'finance',
        targetId: 'native-branch-migration',
        summary: 'Backfilled $techniciansUpdated technicians, '
            '$billsUpdated bills and $incentivesUpdated incentives',
      ),
    );
    writes++;
    await commitIfNeeded(force: true);
    return FinancialBranchBackfillResult(
      techniciansUpdated: techniciansUpdated,
      billsUpdated: billsUpdated,
      incentivesUpdated: incentivesUpdated,
    );
  }

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
    // Keep denormalised names in sync. A user's branch name is displayed in
    // the technician and admin dashboards, while a booking's branch name is
    // displayed to customers. Without this fan-out, a rename is only visible
    // to screens that happen to read the branch collection directly.
    final snapshots = await Future.wait([
      _firestore.collection('users').where('branchId', isEqualTo: branch.id).get(),
      _firestore
          .collection('users')
          .where('nativeBranchId', isEqualTo: branch.id)
          .get(),
      _firestore
          .collection('bookings')
          .where('branchId', isEqualTo: branch.id)
          .get(),
    ]);
    final members = snapshots[0];
    final nativeMembers = snapshots[1];
    final bookings = snapshots[2];

    final memberUpdates = <DocumentReference<Map<String, dynamic>>,
        Map<String, Object?>>{};
    for (final member in members.docs) {
      memberUpdates[member.reference] = {
        'branchName': branch.name.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
    }
    for (final member in nativeMembers.docs) {
      memberUpdates.update(
        member.reference,
        (updates) => {
          ...updates,
          'nativeBranchName': branch.name.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        ifAbsent: () => {
          'nativeBranchName': branch.name.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }

    final writes = <void Function(WriteBatch)>[
      (batch) => batch.update(branchRef, {
            ...branch.toJson(),
            'updatedAt': FieldValue.serverTimestamp(),
          }),
      (batch) => batch.set(
            auditRef,
            _auditData(
              actorId: actorId,
              action: 'branch.updated',
              targetType: 'branch',
              targetId: branch.id,
              branchId: branch.id,
              summary: 'Updated ${branch.name}',
            ),
          ),
      ...memberUpdates.entries.map(
        (entry) => (WriteBatch batch) => batch.update(entry.key, entry.value),
      ),
      ...bookings.docs.map(
        (booking) => (WriteBatch batch) => batch.update(booking.reference, {
              'branchName': branch.name.trim(),
              'updatedAt': FieldValue.serverTimestamp(),
            }),
      ),
    ];
    await _commitInBatches(writes);
  }

  Future<void> _commitInBatches(List<void Function(WriteBatch)> writes) async {
    // Firestore permits up to 500 mutations per batch. Leave headroom for
    // future fields and allow a branch rename to scale beyond one small team.
    for (var start = 0; start < writes.length; start += 450) {
      final batch = _firestore.batch();
      for (final write in writes.skip(start).take(450)) {
        write(batch);
      }
      await batch.commit();
    }
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

class FinancialBranchBackfillResult {
  const FinancialBranchBackfillResult({
    required this.techniciansUpdated,
    required this.billsUpdated,
    required this.incentivesUpdated,
  });

  final int techniciansUpdated;
  final int billsUpdated;
  final int incentivesUpdated;

  int get totalUpdated => techniciansUpdated + billsUpdated + incentivesUpdated;
}
