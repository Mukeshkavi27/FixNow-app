import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums/booking_status.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/estimate.dart';

final estimateRepositoryProvider = Provider<EstimateRepository>((ref) {
  return EstimateRepository(ref.watch(firebaseRefsProvider).firestore);
});

class EstimateRepository {
  EstimateRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<Estimate?> watchForBooking(String bookingId) {
    return _firestore
        .collection('estimates')
        .where('bookingId', isEqualTo: bookingId)
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isEmpty ? null : Estimate.fromFirestore(snapshot.docs.first));
  }

  Future<void> createEstimate(Estimate estimate) async {
    await _firestore.collection('estimates').add(estimate.toJson());
    await _firestore.collection('bookings').doc(estimate.bookingId).update({
      'status': BookingStatus.estimateSent.name,
    });
    await _firestore.collection('notifications').add({
      'title': 'Estimate Sent',
      'body': 'Please review and approve the service estimate.',
      'bookingId': estimate.bookingId,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }

  Future<void> approve(String estimateId, String bookingId) async {
    await _firestore.collection('estimates').doc(estimateId).update({'isApproved': true});
    await _firestore.collection('bookings').doc(bookingId).update({
      'status': BookingStatus.estimateApproved.name,
    });
  }
}
