import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/firebase_providers.dart';
import '../domain/review.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(ref.watch(firebaseRefsProvider).firestore);
});

class ReviewRepository {
  ReviewRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<Review?> watchForBooking(String bookingId) {
    return _firestore.collection('reviews').doc(bookingId).snapshots().map(
          (doc) => doc.exists ? Review.fromFirestore(doc) : null,
        );
  }

  Stream<List<Review>> watchAllReviews({String? branchId}) {
    Query<Map<String, dynamic>> query = _firestore.collection('reviews');
    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query.snapshots().map((snapshot) {
      final reviews = snapshot.docs.map(Review.fromFirestore).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return reviews;
    });
  }

  Future<void> submitReview({
    required String bookingId,
    required String technicianId,
    required String customerId,
    required int rating,
    required String text,
  }) async {
    if (rating < 1 || rating > 5) {
      throw ArgumentError('Rating must be between 1 and 5.');
    }
    final reviewRef = _firestore.collection('reviews').doc(bookingId);
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    await _firestore.runTransaction((transaction) async {
      final booking = await transaction.get(bookingRef);
      final bookingData = booking.data();
      if (bookingData == null) throw StateError('Booking not found.');
      if (bookingData['customerId'] != customerId ||
          bookingData['technicianId'] != technicianId) {
        throw StateError('Review details do not match the booking.');
      }
      final branchId = bookingData['branchId'] as String?;
      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError('Booking has no branch assignment.');
      }
      transaction.set(reviewRef, {
        'bookingId': bookingId,
        'technicianId': technicianId,
        'customerId': customerId,
        'branchId': branchId,
        'rating': rating,
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
