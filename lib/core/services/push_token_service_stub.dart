import 'package:cloud_firestore/cloud_firestore.dart';

class PushTokenService {
  PushTokenService._();

  static final PushTokenService instance = PushTokenService._();

  Future<void> registerTechnician({
    required String userId,
    required FirebaseFirestore firestore,
  }) async {}
}
