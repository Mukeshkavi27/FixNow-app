import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/firebase_providers.dart';
import '../../features/auth/data/auth_repository.dart';
import '../enums/user_role.dart';
import 'branch_info.dart';

final branchRepositoryProvider = Provider<BranchRepository>((ref) {
  return BranchRepository(ref.watch(firebaseRefsProvider).firestore);
});

final branchesProvider = StreamProvider.autoDispose<List<BranchInfo>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final branchId = user?.role == UserRole.branchAdmin ? user?.branchId : null;
  return ref.watch(branchRepositoryProvider).watchBranches(
        branchId: branchId,
        // Branches are live operational data. Returning demo branches here
        // makes a removed branch remain selectable for customers and staff.
        fallbackWhenEmpty: false,
      );
});

class BranchRepository {
  BranchRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _branches =>
      _firestore.collection('branches');

  Stream<List<BranchInfo>> watchBranches({
    String? branchId,
    bool fallbackWhenEmpty = true,
    bool includeInactive = false,
  }) {
    Query<Map<String, dynamic>> query = _branches;
    if (branchId != null && branchId.isNotEmpty) {
      query = query.where(FieldPath.documentId, isEqualTo: branchId);
    } else {
      query = query.orderBy('name');
    }
    return query.snapshots().map(
      (snapshot) {
        final branches = snapshot.docs
            .map((doc) => BranchInfo.fromJson(doc.id, doc.data()))
            .where(
              (branch) =>
                  branch.name.isNotEmpty &&
                  branch.city.isNotEmpty &&
                  (includeInactive || branch.isActive),
            )
            .toList();
        return branches.isEmpty && fallbackWhenEmpty
            ? BranchInfo.fallbackBranches
            : branches;
      },
    );
  }

  Future<void> createBranch(BranchInfo branch) async {
    final doc = _branches.doc();
    final savedBranch = BranchInfo(
      id: doc.id,
      name: branch.name,
      city: branch.city,
      latitude: branch.latitude,
      longitude: branch.longitude,
      aliases: branch.aliases,
      radiusMeters: branch.radiusMeters,
      isActive: branch.isActive,
    );
    await doc.set(savedBranch.toJson());
  }

  Future<void> updateBranch(BranchInfo branch) {
    return _branches.doc(branch.id).update(branch.toJson());
  }
}
