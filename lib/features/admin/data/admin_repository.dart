import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums/user_role.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/domain/app_user.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(firebaseRefsProvider).firestore);
});

class AdminRepository {
  AdminRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<AppUser>> watchTechnicians() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.technician.name)
        .snapshots()
        .map((snap) => snap.docs.map(AppUser.fromFirestore).toList());
  }

  Stream<List<AppUser>> watchCustomers() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.customer.name)
        .snapshots()
        .map((snap) => snap.docs.map(AppUser.fromFirestore).toList());
  }

  Future<void> setTechnicianActive(String uid, bool isActive) {
    return _firestore.collection('users').doc(uid).update({'isActive': isActive});
  }
}
