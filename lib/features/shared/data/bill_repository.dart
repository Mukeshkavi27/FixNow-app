import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums/booking_status.dart';
import '../../../core/providers/firebase_providers.dart';

final billRepositoryProvider = Provider<BillRepository>((ref) {
  return BillRepository(ref.watch(firebaseRefsProvider).firestore);
});

class BillRepository {
  BillRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchCustomerBills(String customerId) {
    return _firestore.collection('bills').where('customerId', isEqualTo: customerId).snapshots();
  }

  Future<void> generateBill({
    required String bookingId,
    required String customerId,
    required String technicianId,
    required double amount,
  }) async {
    await _firestore.collection('bills').add({
      'bookingId': bookingId,
      'customerId': customerId,
      'technicianId': technicianId,
      'amount': amount,
      'createdAt': FieldValue.serverTimestamp(),
      'isPaid': false,
    });
    await _firestore.collection('bookings').doc(bookingId).update({
      'status': BookingStatus.billGenerated.name,
    });
  }
}
