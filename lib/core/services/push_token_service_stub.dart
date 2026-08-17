import 'package:cloud_firestore/cloud_firestore.dart';

class PushTokenService {
  PushTokenService._();

  static final PushTokenService instance = PushTokenService._();

  Future<void> registerUser({
    required String userId,
    required String role,
    String? branchId,
    required FirebaseFirestore firestore,
  }) async {}

  Future<void> registerTechnician({
    required String userId,
    required FirebaseFirestore firestore,
  }) => registerUser(
        userId: userId,
        role: 'technician',
        branchId: null,
        firestore: firestore,
      );
}
