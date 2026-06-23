import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums/account_status.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/domain/app_user.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(firebaseRefsProvider).firestore);
});

class AdminRepository {
  AdminRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<AppUser>> watchTechnicians({String? branchId}) {
    var query = _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.technician.name);
    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query.snapshots().map((snap) => snap.docs.map(AppUser.fromFirestore).toList());
  }

  Stream<List<AppUser>> watchCustomers({String? branchId}) {
    var query = _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.customer.name);
    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query.snapshots().map((snap) => snap.docs.map(AppUser.fromFirestore).toList());
  }

  Stream<List<AppUser>> watchPendingTechnicianRequests({String? branchId}) {
    var query = _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.technician.name)
        .where('accountStatus', isEqualTo: AccountStatus.pendingApproval.name);
    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query.snapshots().map((snap) => snap.docs.map(AppUser.fromFirestore).toList());
  }

  Future<void> setTechnicianActive(String uid, bool isActive) {
    return _firestore.collection('users').doc(uid).update({'isActive': isActive});
  }

  Future<void> approveTechnicianRequest({
    required String uid,
    required String branchId,
    required String branchName,
  }) {
    return _firestore.collection('users').doc(uid).update({
      'isActive': true,
      'accountStatus': AccountStatus.approved.name,
      'branchId': branchId,
      'branchName': branchName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectTechnicianRequest(String uid) {
    return _firestore.collection('users').doc(uid).update({
      'isActive': false,
      'accountStatus': AccountStatus.rejected.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
