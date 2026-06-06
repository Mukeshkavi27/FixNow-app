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

  Future<void> submitReview({
    required String bookingId,
    required String technicianId,
    required String customerId,
    required int rating,
    required String text,
  }) {
    final review = Review(
      id: '',
      bookingId: bookingId,
      technicianId: technicianId,
      customerId: customerId,
      rating: rating,
      text: text,
      createdAt: DateTime.now(),
    );
    return _firestore.collection('reviews').add(review.toJson());
  }
}
