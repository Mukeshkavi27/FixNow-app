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

  Future<void> submitReview({
    required String bookingId,
    required String technicianId,
    required String customerId,
    required int rating,
    required String text,
  }) {
    if (rating < 1 || rating > 5) {
      throw ArgumentError('Rating must be between 1 and 5.');
    }
    final review = Review(
      id: bookingId,
      bookingId: bookingId,
      technicianId: technicianId,
      customerId: customerId,
      rating: rating,
      text: text.trim(),
      createdAt: DateTime.now(),
    );
    return _firestore.collection('reviews').doc(bookingId).set({
      ...review.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
