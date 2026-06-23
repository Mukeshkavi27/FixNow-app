import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/firebase_providers.dart';
import 'branch_info.dart';

final branchRepositoryProvider = Provider<BranchRepository>((ref) {
  return BranchRepository(ref.watch(firebaseRefsProvider).firestore);
});

final branchesProvider = StreamProvider.autoDispose<List<BranchInfo>>((ref) {
  return ref.watch(branchRepositoryProvider).watchBranches();
});

class BranchRepository {
  BranchRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _branches =>
      _firestore.collection('branches');

  Stream<List<BranchInfo>> watchBranches() {
    return _branches
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => BranchInfo.fromJson(doc.id, doc.data()))
              .where((branch) =>
                  branch.name.isNotEmpty &&
                  branch.city.isNotEmpty)
              .toList(),
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
    );
    await doc.set(savedBranch.toJson());
  }

  Future<void> updateBranch(BranchInfo branch) {
    return _branches.doc(branch.id).update(branch.toJson());
  }
}
