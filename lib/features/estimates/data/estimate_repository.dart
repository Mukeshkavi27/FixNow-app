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
    return _firestore.collection('estimates').doc(bookingId).snapshots().map(
        (snapshot) =>
            snapshot.exists ? Estimate.fromFirestore(snapshot) : null);
  }

  Future<void> createEstimate(Estimate estimate) async {
    if (estimate.total <= 0) {
      throw ArgumentError('Estimate total must be greater than zero.');
    }
    final estimateRef =
        _firestore.collection('estimates').doc(estimate.bookingId);
    final bookingRef =
        _firestore.collection('bookings').doc(estimate.bookingId);
    await _firestore.runTransaction((transaction) async {
      final booking = await transaction.get(bookingRef);
      final data = booking.data();
      if (data == null) throw StateError('Booking not found.');
      final status =
          BookingStatus.fromString(data['status'] as String? ?? 'booked');
      if (data['technicianId'] != estimate.technicianId ||
          (status != BookingStatus.customerConfirmedArrival &&
              status != BookingStatus.estimateRejected)) {
        throw StateError('Estimate cannot be created for this booking.');
      }
      final notificationRef = _firestore.collection('notifications').doc();
      transaction.set(estimateRef, {
        ...estimate.toJson(),
        'createdAt': FieldValue.serverTimestamp(),
        'isRejected': false,
      });
      transaction.update(bookingRef, {
        'status': BookingStatus.estimateSent.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(notificationRef, {
        'userId': data['customerId'],
        'bookingId': estimate.bookingId,
        'type': 'estimateSent',
        'title': 'Estimate approval required',
        'body':
            'Please review and approve the estimate for ${data['applianceType'] ?? 'your service'}.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> approve(String estimateId, String bookingId) async {
    final estimateRef = _firestore.collection('estimates').doc(estimateId);
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    await _firestore.runTransaction((transaction) async {
      final estimate = await transaction.get(estimateRef);
      final booking = await transaction.get(bookingRef);
      if (!estimate.exists || !booking.exists) {
        throw StateError('Estimate or booking not found.');
      }
      if (estimate.data()?['isApproved'] == true ||
          booking.data()?['status'] != BookingStatus.estimateSent.name) {
        throw StateError('This estimate can no longer be approved.');
      }
      transaction.update(estimateRef, {
        'isApproved': true,
        'approvedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(bookingRef, {
        'status': BookingStatus.estimateApproved.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(_firestore.collection('notifications').doc(), {
        'userId': estimate.data()?['technicianId'],
        'bookingId': bookingId,
        'type': 'estimateApproved',
        'title': 'Estimate approved',
        'body': 'Customer approved the estimate. You can start the service.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> reject(String estimateId, String bookingId) async {
    final estimateRef = _firestore.collection('estimates').doc(estimateId);
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    await _firestore.runTransaction((transaction) async {
      final estimate = await transaction.get(estimateRef);
      final booking = await transaction.get(bookingRef);
      if (!estimate.exists || !booking.exists) {
        throw StateError('Estimate or booking not found.');
      }
      if (booking.data()?['status'] != BookingStatus.estimateSent.name) {
        throw StateError('This estimate can no longer be rejected.');
      }
      transaction.update(estimateRef, {
        'isApproved': false,
        'isRejected': true,
        'rejectedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(bookingRef, {
        'status': BookingStatus.estimateRejected.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(_firestore.collection('notifications').doc(), {
        'userId': estimate.data()?['technicianId'],
        'bookingId': bookingId,
        'type': 'estimateRejected',
        'title': 'Estimate rejected',
        'body': 'Customer rejected the estimate. Please send a revised one.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
