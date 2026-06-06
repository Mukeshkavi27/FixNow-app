import 'package:cloud_firestore/cloud_firestore.dart';

class Review {
  const Review({
    required this.id,
    required this.bookingId,
    required this.technicianId,
    required this.customerId,
    required this.rating,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String bookingId;
  final String technicianId;
  final String customerId;
  final int rating;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'bookingId': bookingId,
        'technicianId': technicianId,
        'customerId': customerId,
        'rating': rating,
        'text': text,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
